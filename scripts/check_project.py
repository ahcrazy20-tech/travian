#!/usr/bin/env python3
"""Static sanity checks for the UtatarApp Xcode project.

Catches the class of mistakes that break an `xcodebuild` run before we ever
have to burn macOS CI minutes:

  * Swift files on disk that are not in the target's Sources build phase
  * File references in project.pbxproj that point at missing files
  * Xcode schemes whose BlueprintIdentifier does not match a real target
  * more than one @main entry point
  * malformed Info.plist / asset-catalog JSON
  * Info.plist keys that point at resources the project does not have
  * unbalanced braces/parens in a Swift file (truncated or bad merge)
  * a missing app-icon image while ASSETCATALOG_COMPILER_APPICON_NAME is set

Usage: python3 scripts/check_project.py [path/to/repo]
"""
from __future__ import annotations

import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from collections import Counter

FAIL = "ERROR"
WARN = "WARN"

errors: list[tuple[str, str]] = []


def report(kind: str, msg: str) -> None:
    errors.append((kind, msg))
    print(f"  {kind:5s} {msg}")


def strip_swift_noise(src: str) -> str:
    """Remove comments and string literals so brace counting is meaningful."""
    src = re.sub(r'"""(?:[^"\\]|\\.|"(?!""))*"""', '""', src, flags=re.S)  # multiline strings
    src = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', src)                        # normal strings
    src = re.sub(r'(?:^|\n)\s*#if\b[^\n]*', '\n', src)
    src = re.sub(r"//[^\n]*", "", src)                                      # line comments
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)                        # block comments
    return src



def blank_out(src: str) -> str:
    """Blank out comments and string literals while preserving line/col layout."""
    out, i, n = [], 0, len(src)
    while i < n:
        two = src[i:i + 2]
        three = src[i:i + 3]
        if three == '\"\"\"':
            j = src.find('\"\"\"', i + 3)
            j = n if j < 0 else j + 3
            out.append("".join("\n" if c == "\n" else " " for c in src[i:j]))
            i = j
        elif two == "//":
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif two == "/*":
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append("".join("\n" if c == "\n" else " " for c in src[i:j]))
            i = j
        elif two == '\"\"\"':
            j = src.find('\"\"\"', i + 3)
            j = n if j < 0 else j + 3
            out.append("".join("\n" if c == "\n" else " " for c in src[i:j]))
            i = j
        elif src[i] == '"':
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == "\\" else 1
            j = min(j + 1, n)
            out.append(src[i] + " " * (j - i - 1) + ('"' if j - i >= 2 else ""))
            i = j
        else:
            out.append(src[i])
            i += 1
    return "".join(out)


TYPE_RX = re.compile(
    r'^\s*(?:@[A-Za-z]+\s+)*(?:public |internal |private |fileprivate |open )?'
    r'(?:final )?(struct|class|enum|extension)\s+([A-Za-z_][A-Za-z0-9_]*)')
FUNC_RX = re.compile(
    r'^\s*(?P<access>open |public |internal |private |fileprivate )?'
    r'(?:@[A-Za-z]+(?:\([^)]*\))?\s+)*'
    r'(?:static |class |override |mutating |convenience |nonisolated )*'
    r'func\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*|init)\b')
VAR_RX = re.compile(
    r'^\s*(?P<access>open |public |internal |private |fileprivate )?'
    r'(?:@[A-Za-z]+(?:\([^)]*\))?\s+)*'
    r'(?:static |class |weak |unowned |lazy |final |MainActor )*'
    r'var\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\b')


def signature_of(lines, idx):
    """Full declaration signature (spans continuation lines) normalised to one string."""
    buf, seen_open = [], False
    for extra in range(0, 6):
        if idx + extra >= len(lines):
            break
        cur = lines[idx + extra]
        buf.append(cur)
        seen_open = seen_open or "(" in cur
        joined = "".join(buf)
        if seen_open and joined.count("(") == joined.count(")") and ("{" in cur or "->" in cur):
            break
        if not seen_open and ("{" in cur or ":" in cur):
            break
    sig = re.sub(r"\s+", " ", " ".join(buf)).strip()
    sig = sig.split("{")[0].strip()
    return sig


def scan_declarations(paths):
    """{type: {member: [(access, file, line, signature), ...]}} for members declared in a class/struct/extension body."""
    decls = {}
    for path in paths:
        clean = blank_out(open(path, encoding="utf-8").read())
        lines = clean.splitlines()
        stack = []          # [(type_name, depth_when_opened)]
        depth = 0
        for lineno, line in enumerate(lines, 1):
            tm = TYPE_RX.match(line)
            if tm:
                stack.append((tm.group(2), depth))
            fm, vm = FUNC_RX.match(line), VAR_RX.match(line)
            hit = fm or vm
            if hit and stack:
                owner = stack[-1][0]
                # only direct members of the type: the type's own opening brace
                # already pushed depth to owner_depth+1, so members sit exactly
                # one level deeper; anything further is inside a nested body.
                if depth == stack[-1][1] + 1:
                    is_func = bool(fm)
                    sig = signature_of(lines, lineno - 1) if is_func else "var"
                    decls.setdefault(owner, {}).setdefault(hit.group("name"), []).append(
                        ((hit.group("access") or "internal").strip(), os.path.basename(path), lineno, sig, is_func))
            depth += line.count("{") - line.count("}")
            while stack and depth <= stack[-1][1]:
                stack.pop()
    return decls


def find_pbxproj(repo: str) -> str | None:
    for root, dirs, files in os.walk(repo):
        dirs[:] = [d for d in dirs if d not in (".git", "node_modules", "build", "DerivedData")]
        if "project.pbxproj" in files and root.endswith(".xcodeproj"):
            return os.path.join(root, "project.pbxproj")
    return None


def main() -> int:
    repo = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
    print(f"🔍 Checking Xcode project in {repo}\n")

    pbx_path = find_pbxproj(repo)
    if not pbx_path:
        report(FAIL, "no project.pbxproj found (is the .xcodeproj committed?)")
        return finish()

    proj_dir = os.path.dirname(os.path.dirname(pbx_path))  # .../UtatarApp
    pbx = open(pbx_path, encoding="utf-8").read()
    print(f"  📄 project: {os.path.relpath(pbx_path, repo)}")

    # ---- locate the source folder (the group that holds the Swift files) -------
    swift_files = []
    for root, dirs, files in os.walk(proj_dir):
        dirs[:] = [d for d in dirs if d not in (".git", "build", "DerivedData", "Pods", "SourcePackages")]
        swift_files += [os.path.join(root, f) for f in files if f.endswith(".swift")]
    src_dir = os.path.dirname(swift_files[0]) if swift_files else proj_dir
    on_disk = sorted(os.listdir(src_dir)) if os.path.isdir(src_dir) else []

    # ---- 1. file references exist on disk -------------------------------------
    file_refs = dict(re.findall(r'([0-9A-F]{8,24}) /\* .*? \*/ = \{isa = PBXFileReference;[^}]*?path = "?([^";]+)"?;', pbx))
    if not file_refs:
        file_refs = dict(re.findall(r'([0-9A-F]{8,24}) = \{isa = PBXFileReference;[^}]*?path = "?([^";]+)"?;', pbx))
    for uuid, rel in file_refs.items():
        name = os.path.basename(rel)
        if rel.endswith(".app"):
            continue  # product reference lives in the build dir, not in the repo
        if not any(os.path.exists(os.path.join(base, name)) for base in (src_dir, proj_dir, os.path.join(proj_dir, rel))):
            report(FAIL, f"project.pbxproj references '{rel}' but no such file exists in the project folder")

    # ---- 2. every Swift file on disk is compiled -------------------------------
    swift_on_disk = {f for f in on_disk if f.endswith(".swift")}
    sources_phase = re.search(r'isa = PBXSourcesBuildPhase;.*?files = \((.*?)\);', pbx, flags=re.S)
    in_sources = set(re.findall(r'/\* (\S+\.swift) in Sources \*/', sources_phase.group(1))) if sources_phase else set()
    for f in sorted(swift_on_disk - in_sources):
        report(FAIL, f"{f} is not in the target's Compile Sources phase (it will never be compiled)")
    for f in sorted(in_sources - swift_on_disk):
        report(FAIL, f"Compile Sources lists {f}, which does not exist in {os.path.basename(src_dir)}/")

    # ---- 3. resources phase ----------------------------------------------------
    res_phase = re.search(r'isa = PBXResourcesBuildPhase;.*?files = \((.*?)\n\t\t\t\);', pbx, flags=re.S)
    in_resources = set(re.findall(r'/\* (.+?) in Resources \*/', res_phase.group(1))) if res_phase else set()
    for f in sorted({x for x in on_disk if x.endswith(".xcassets")} - in_resources):
        report(FAIL, f"{f} is not in the Copy Bundle Resources phase (assets will be missing)")

    # ---- 4. build settings -----------------------------------------------------
    settings = dict(re.findall(r'^\t*(?:/\* [^*]* \*/ = )?([A-Z0-9_]+) = (.*);$', pbx, flags=re.M))

    def setting(key: str) -> str:
        m = re.search(rf'^\s*{key} = (.*?);\s*$', pbx, flags=re.M)
        return m.group(1).strip('"') if m else ""

    deploy = setting("IPHONEOS_DEPLOYMENT_TARGET")
    if not deploy:
        report(FAIL, "IPHONEOS_DEPLOYMENT_TARGET is not set")
    else:
        major = float(deploy)
        if major < 15:
            report(WARN, f"IPHONEOS_DEPLOYMENT_TARGET {deploy} is very old; modern Xcode supports 15.0+")
        elif major > 26:
            report(FAIL, f"IPHONEOS_DEPLOYMENT_TARGET {deploy} is newer than any shipping iOS SDK")
        else:
            print(f"  ✅ deployment target iOS {deploy}")

    if setting("SWIFT_VERSION") not in ("5.0", "6.0"):
        report(WARN, f"SWIFT_VERSION='{setting('SWIFT_VERSION')}' (expected 5.0 or 6.0)")

    info_plist_rel = setting("INFOPLIST_FILE")
    info_plist = os.path.join(proj_dir, info_plist_rel) if info_plist_rel else ""
    gen = setting("GENERATE_INFOPLIST_FILE") == "YES"
    if info_plist_rel and not os.path.exists(info_plist):
        report(FAIL, f"INFOPLIST_FILE points at '{info_plist_rel}' which does not exist")

    # ---- 5. one and only one @main --------------------------------------------
    mains = []
    for path in swift_files:
        src = open(path, encoding="utf-8").read()
        rel = os.path.relpath(path, repo)
        if re.search(r'^\s*@main\b', src, flags=re.M):
            mains.append(rel)
        if re.search(r'^\s*@(?:UIApplication|NSApplication)Main\b', src, flags=re.M):
            mains.append(rel + " (@UIApplicationMain)")
        if len(src) < 4:
            report(FAIL, f"{rel} looks empty/truncated")
        stripped = strip_swift_noise(src)
        for a, b, name in (("{", "}", "braces"), ("(", ")", "parens"), ("[", "]", "brackets")):
            if stripped.count(a) != stripped.count(b):
                report(FAIL, f"{rel}: unbalanced {name} ({stripped.count(a)} '{a}' vs {stripped.count(b)} '{b}')")
    if len(mains) > 1:
        report(FAIL, f"multiple app entry points found: {', '.join(mains)} (linker error: 'multiple @main')")
    elif len(mains) == 1:
        print(f"  ✅ single app entry point ({mains[0]})")
    else:
        report(FAIL, "no @main entry point found -> the .app will not launch")

    # ---- 6. Info.plist content -------------------------------------------------
    if info_plist_rel and os.path.exists(info_plist):
        try:
            root = ET.parse(info_plist).getroot()
            keys = {k.text for k in root.iter("key")}
            for req in ("CFBundleExecutable", "CFBundleIdentifier"):
                if req not in keys:
                    report(FAIL, f"Info.plist is missing required key {req}")
            if "UIRequiredDeviceCapabilities" in keys:
                txt = ET.tostring(root, encoding="unicode")
                if "armv7" in txt:
                    report(FAIL, "Info.plist requires 'armv7' device capability - no iOS 16+ device has it; remove it")
            def plist_value(key_name):
                top = root.find('dict')
                kids = list(top) if top is not None else []
                for i, node in enumerate(kids):
                    if node.tag == 'key' and (node.text or '') == key_name and i + 1 < len(kids):
                        return kids[i + 1]
                return None

            story = plist_value('UILaunchStoryboardName')
            if story is not None:
                name = story.text or ""
                if not any(f == f"{name}.storyboard" or f == f"{name}.xib" for f in on_disk):
                    report(FAIL, f"Info.plist UILaunchStoryboardName='{name}' but no {name}.storyboard/.xib exists in {os.path.basename(src_dir)}/")
            if gen and {"CFBundleShortVersionString", "CFBundleVersion"} & keys:
                if "$(MARKETING_VERSION)" not in ET.tostring(root, encoding="unicode"):
                    report(WARN, "Info.plist hardcodes version keys while GENERATE_INFOPLIST_FILE=YES; prefer $(MARKETING_VERSION)")
            print("  ✅ Info.plist is well-formed XML")
        except ET.ParseError as exc:
            report(FAIL, f"Info.plist is not valid XML: {exc}")

    # ---- 6b. APIs newer than the deployment target ---------------------------
    try:
        deploy_major = float(deploy) if deploy else 0.0
    except ValueError:
        deploy_major = 0.0
    TOO_NEW = {
        16.0: [
            (r"(?<![\w.])\.tint\(", ".tint(...)  (iOS 16+)"),
            (r"\bContentUnavailableView\b", "ContentUnavailableView (iOS 17+)"),
            (r"\bNavigationStack\b", "NavigationStack (iOS 16+)"),
            (r"\bpresentationDetents\b", ".presentationDetents (iOS 16+)"),
        ],
        17.0: [
            (r"\bContentUnavailableView\b", "ContentUnavailableView (iOS 17+)"),
            (r"\bsymbolEffect\b", ".symbolEffect (iOS 17+)"),
            (r"#Preview\b", "#Preview macro (needs iOS 17 target)"),
            (r"\bscrollTargetLayout\b", ".scrollTargetLayout (iOS 17+)"),
        ],
    }
    for min_os, patterns in TOO_NEW.items():
        if deploy_major and deploy_major >= min_os:
            continue
        for rx, label in patterns:
            for path in swift_files:
                txt = blank_out(open(path, encoding="utf-8").read())
                # an API guarded by #available is fine
                guarded = re.search(rf"#available\([^)]*iOS\s*{int(min_os)}[^)]*\)[^{{]*{{[^}}]*{rx}", txt, flags=re.S)
                for m in re.finditer(rx, txt):
                    line_no = txt[:m.start()].count("\n") + 1
                    if guarded and abs(txt[:m.start()].count("\n") - txt[:guarded.start()].count("\n")) < 8:
                        continue
                    report(FAIL, f"{os.path.basename(path)}:{line_no} uses {label} but IPHONEOS_DEPLOYMENT_TARGET is {deploy} "
                                 f"- either guard it with #available or raise the target")
                    break

    # ---- 7. asset catalog ------------------------------------------------------
    catalog = os.path.join(src_dir, "Assets.xcassets")
    if os.path.isdir(catalog):
        for root, dirs, files in os.walk(catalog):
            for f in files:
                if f == "Contents.json":
                    p = os.path.join(root, f)
                    try:
                        data = json.load(open(p, encoding="utf-8"))
                    except json.JSONDecodeError as exc:
                        report(FAIL, f"{os.path.relpath(p, repo)} is not valid JSON: {exc}")
                        continue
                    for img in data.get("images", []):
                        if "filename" in img and not os.path.exists(os.path.join(root, img["filename"])):
                            report(FAIL, f"{os.path.relpath(p, repo)} references missing image '{img['filename']}'")
        appicon_name = setting("ASSETCATALOG_COMPILER_APPICON_NAME")
        if appicon_name:
            set_dir = os.path.join(catalog, f"{appicon_name}.appiconset")
            if not os.path.isdir(set_dir):
                report(FAIL, f"ASSETCATALOG_COMPILER_APPICON_NAME='{appicon_name}' but {appicon_name}.appiconset is missing")
            else:
                data = json.load(open(os.path.join(set_dir, "Contents.json"), encoding="utf-8"))
                entries = data.get("images", [])
                used = {img.get("filename") for img in entries if img.get("filename")}
                if not used:
                    report(FAIL, f"{appicon_name}.appiconset has no image file (actool: 'None of the input catalogs contained a matching app icon set')")
                else:
                    print(f"  ✅ app icon set '{appicon_name}': {len(used)} image(s)")
                    if all(i.get("idiom") == "universal" for i in entries) and deploy_major and deploy_major < 17:
                        report(WARN, f"{appicon_name}.appiconset only has the single-size (universal 1024) icon while "
                                     f"IPHONEOS_DEPLOYMENT_TARGET is {deploy} - older targets want the full size list")
                for f in sorted(os.listdir(set_dir)):
                    if f.endswith((".png", ".pngx")) and f not in used:
                        report(WARN, f"{appicon_name}.appiconset/{f} is not referenced in Contents.json (actool ignores it)")
    else:
        report(WARN, "no Assets.xcassets found")

    # ---- 8. schemes ------------------------------------------------------------
    target_ids = set(re.findall(r'([0-9A-F]{24}|A[0-9A-F]{7}) /\* .*? \*/ = \{\n\s*isa = PBXNativeTarget;', pbx))
    if not target_ids:
        target_ids = set(re.findall(r'([0-9A-F]{24}|A[0-9A-F]{7}) = \{\n\s*isa = PBXNativeTarget;', pbx))
    scheme_dir = os.path.join(os.path.dirname(pbx_path), "xcshareddata", "xcschemes")
    schemes = [f for f in os.listdir(scheme_dir)] if os.path.isdir(scheme_dir) else []
    if not schemes:
        report(WARN, "no shared .xcscheme - `xcodebuild -scheme` relies on Xcode's auto-generated scheme; commit a shared scheme for CI reliability")
    for s in schemes:
        if not s.endswith(".xcscheme"):
            continue
        body = open(os.path.join(scheme_dir, s), encoding="utf-8").read()
        ids = set(re.findall(r'BlueprintIdentifier = "([^"]+)"', body))
        if not ids:
            report(FAIL, f"{s}: no BlueprintIdentifier found")
        for bid in ids:
            if bid not in target_ids:
                report(FAIL, f"{s}: BlueprintIdentifier {bid} does not match any target in project.pbxproj")
        if "buildForArchiving" not in body:
            report(WARN, f"{s}: BuildActionEntry has no buildForArchiving (archive step may fail)")
        if s == "UtatarApp.xcscheme" or ids & target_ids:
            print(f"  ✅ shared scheme {s} -> {', '.join(sorted(ids))}")

    # ---- 9. duplicate declarations + cross-file private access ----------------
    decls = scan_declarations(swift_files)
    for type_name, members in sorted(decls.items()):
        for member, locs in sorted(members.items()):
            # funcs may be overloaded -> only identical signatures are redeclarations
            groups = {}
            for a, f, ln, sig, is_func in locs:
                groups.setdefault(sig if is_func else "var", []).append((f, ln))
            for sig, spots in groups.items():
                if len(spots) > 1:
                    where = ", ".join(f"{f}:{ln}" for f, ln in spots)
                    report(FAIL, f"invalid redeclaration: {type_name}.{member} declared {len(spots)}x ({where})")
        nonprivate_files = {f for name, locs in members.items() for a, f, _, _, _ in locs if a != "private"}
        for member, locs in members.items():
            acc, owner_file, owner_line = locs[0][0], locs[0][1], locs[0][2]
            if acc not in ("private", "fileprivate"):
                continue
            for other in sorted(nonprivate_files - {owner_file}):
                other_path = os.path.join(src_dir, other)
                if not os.path.exists(other_path):
                    continue
                otxt = blank_out(open(other_path, encoding="utf-8").read())
                calls_it = re.search(rf"(?:\.|self\.){re.escape(member)}\s*\(", otxt) or (
                    re.search(rf"extension\s+{re.escape(type_name)}\b", otxt) and re.search(rf"(?<![A-Za-z0-9_.]){re.escape(member)}\s*\(", otxt))
                if calls_it and re.search(rf"\b{re.escape(type_name)}\b", otxt):
                    report(FAIL, f"'{other}' calls {type_name}.{member}() which is {acc} (declared in {owner_file}:{owner_line}) - "
                                 f"Swift private members are file-scoped")

    # ---- 10. CI workflow --------------------------------------------------------
    wf_dir = os.path.join(repo, ".github", "workflows")
    if os.path.isdir(wf_dir):
        for f in sorted(os.listdir(wf_dir)):
            if not f.endswith((".yml", ".yaml")):
                continue
            txt = open(os.path.join(wf_dir, f), encoding="utf-8").read()
            for bad, why in (
                ("| xcpretty", "xcpretty is not preinstalled on GitHub macOS runners - the pipe hides the real build result"),
                ("runs-on: macos-14", "macos-14 runners are deprecated (fully unsupported Nov 2026) - use macos-latest"),
                ("actions/cache@v3", "actions/cache@v3 runs on Node 16 and is deprecated - use @v4"),
                ("actions/checkout@v2", "actions/checkout@v2 is retired - use @v4"),
                ("actions/upload-artifact@v3", "upload-artifact@v3 is retired - use @v4"),
                ("name: macOS-12", "macOS 12 image is retired"),
            ):
                if bad in txt:
                    report(WARN, f".github/workflows/{f}: {bad} — {why}")
            if re.search(r"^\s+paths:", txt, flags=re.M) and "workflow" not in txt.split("paths:")[1][:400].replace("\n", " "):
                report(WARN, f".github/workflows/{f}: a `paths:` filter can make pushes look like they 'never start a build'")
    return finish()


def finish() -> int:
    errs = [m for k, m in errors if k == FAIL]
    warns = [m for k, m in errors if k == WARN]
    print()
    if warns:
        print(f"⚠️  {len(warns)} warning(s)")
    if errs:
        print(f"❌ {len(errs)} error(s) found - fix them before building")
        return 1
    print("✅ no project-level errors found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
