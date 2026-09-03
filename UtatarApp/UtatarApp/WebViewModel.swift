import Foundation
import UIKit
import WebKit
import Security
import Combine
import UserNotifications


/// تخزين آمن على الجهاز (Keychain) — بيانات الدخول مش بتخرج من الموبايل خالص
enum Keychain {
    static let service = "utatar-app"

    static func set(_ value: String, forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func del(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

class WebViewModel: NSObject, ObservableObject {
    @Published var isLoading = true
    @Published var currentURL: String = ""
    @Published var showAlert = false
    @Published var alertMessage = ""
    @Published var isAutomationEnabled = false
    
    // Automation settings (محفوظة بين الجلسات في UserDefaults)
    @Published var autoCollectResources: Bool = false { didSet { UD.set(autoCollectResources, forKey: "autoCollect") } }
    @Published var autoBuildQueue: Bool = false { didSet { UD.set(autoBuildQueue, forKey: "autoBuild") } }
    @Published var autoTrainTroops: Bool = false { didSet { UD.set(autoTrainTroops, forKey: "autoTrain"); if autoTrainTroops { injectAutoTrain() } } }
    @Published var autoSpyEnabled: Bool = false { didSet { UD.set(autoSpyEnabled, forKey: "autoSpy") } }
    @Published var autoTrainCount: Int = 10 { didSet { UD.set(autoTrainCount, forKey: "autoTrainCount") } }
    @Published var autoAttackCount: Int = 50 { didSet { UD.set(autoAttackCount, forKey: "autoAttackCount") } }
    @Published var autoRetreatEnabled: Bool = false { didSet { UD.set(autoRetreatEnabled, forKey: "autoRetreat") } }
    @Published var retreatX: Int = 0 { didSet { UD.set(retreatX, forKey: "retreatX") } }
    @Published var retreatY: Int = 0 { didSet { UD.set(retreatY, forKey: "retreatY") } }
    @Published var manualSpyX: String = "" { didSet { UD.set(manualSpyX, forKey: "manualSpyX") } }
    @Published var manualSpyY: String = "" { didSet { UD.set(manualSpyY, forKey: "manualSpyY") } }
    @Published var trainCounts: [String: String] = [:] { didSet { UD.set(trainCounts, forKey: "trainCounts") } }

    /// المهمة اللي في الطريق: تجسس / هجوم / هروب — بتتنفذ لما صفحة a2b تفتح.
    enum PendingAction {
        case spy(x: Int, y: Int, name: String)
        case attack(x: Int, y: Int, name: String)
        case retreat
    }
    private var pendingAction: PendingAction?
    private var actionStartedAt = Date.distantPast
    @Published var attackAlerts: Bool = true { didSet { UD.set(attackAlerts, forKey: "attackAlerts") } }
    @Published var resourceFullAlerts: Bool = true { didSet { UD.set(resourceFullAlerts, forKey: "resFullAlerts") } }
    @Published var buildCompleteAlerts: Bool = true { didSet { UD.set(buildCompleteAlerts, forKey: "buildAlerts") } }
    private let UD = UserDefaults.standard
    
    // Game state
    @Published var woodAmount: String = "0"
    @Published var clayAmount: String = "0"
    @Published var ironAmount: String = "0"
    @Published var wheatAmount: String = "0"
    @Published var wheatProduction: String = "0"

    // ===== الحالة الحقيقية من اللعبة (GameEngine) =====
    let engine = GameEngine()
    @Published var pageKind: String = ""
    @Published var gameResources: GameResources?
    @Published var homeTroops: [HomeUnit] = []
    @Published var trainableUnits: [TrainableUnit] = []
    @Published var mapVillages: [MapVillage] = []
    @Published var spyReports: [ScoutReport] = []
    @Published var gameLog: String = ""
    @Published var isScanningMap = false
    @Published var diagnosticsOutput: String = ""
    @Published var activityLog: [String] = []
    /// كل صفحة بتتفتح تتسجل هنا أوتوماتك (بتفضل محفوظة حتى لو التطبيق اتقفل).
    @Published var pageRecords: String = "" { didSet { UD.set(pageRecords, forKey: "pageRecords") } }
    /// عنوان آخر صفحة تدريب نجحت — عشان التدريب الأوتوماتيك يروحلها لوحده
    @Published var barracksPath: String = "" { didSet { UD.set(barracksPath, forKey: "barracksPath") } }
    /// مهلة بعد تدريب ناجح: منكررش التدريب على اللعبة كل 30 ثانية
    private var trainCooldownUntil = Date.distantPast
    /// أنواع الجنود الملقوطة من الثكنة — محفوظة دايمًا حتى لو خرجت من الصفحة
    @Published var savedTroopTypes: [[String: Any]] = [] { didSet { UD.set(savedTroopTypes, forKey: "savedTroopTypes") } }
    /// الدقيقة اللي هيتدرب بعدها تاني (التدريب المستمر)
    @Published var trainIntervalMin: Int = 10 { didSet { UD.set(trainIntervalMin, forKey: "trainIntervalMin") } }
    private var nextQueuedTrainAt = Date.distantPast
    private var barracksHintShown = false
    /// أول مرة بنعرف فيها إن الموارد كانت ناقصة (نمنع سبام السجل)
    private var lastShortageLogAt = Date.distantPast
    /// ضغطة التدريب الحقيقية المسجلة من إيدك — بنعيد نفس الطلب بالظبط كل فترة
    @Published var lastTrainPost: [String: String] = [:] { didSet { UD.set(lastTrainPost, forKey: "lastTrainPost") } }
    /// حالة تنبيه الهجوم للعرض المباشر في اللوحة
    @Published var alertStatus: String = "" { didSet { UD.set(alertStatus, forKey: "alertStatus") } }
    /// القرّاص: نهب تلقائي من قائمة النهب كل فترة محددة
    @Published var autoFarmEnabled: Bool = false { didSet { UD.set(autoFarmEnabled, forKey: "autoFarmEnabled") } }
    @Published var farmIntervalMin: Int = 30 { didSet { UD.set(farmIntervalMin, forKey: "farmIntervalMin") } }
    private var nextFarmAt = Date.distantPast
    private var farmInfoShown = false
    private var lastAlertNotifyAt = Date.distantPast
    private var lastAlertLoadCheck = Date.distantPast
    /// بعد إطلاق هروب: نستنى 10 دقايق قبل هروب تاني (علامة att1 بتفضل ظاهرة طول ما الهجوم في السكة)
    private var lastRetreatAt = Date.distantPast

    // MARK: - حفظ بيانات الدخول + الدخول التلقائي لما الجلسة تقفل
    @Published var autoLoginEnabled: Bool = true { didSet { UD.set(autoLoginEnabled, forKey: "autoLogin") } }
    @Published var hasSavedLogin = false
    @Published var loginStatus = ""
    private var autoLoginTries = 0
    private var autoLoginWindowAt = Date.distantPast
    private var lastAutoLoginAt = Date.distantPast

    /// 🔐 حفظ الداتا: الـ Keychain الأول — ولو مش متاح على الجهاز (TrollStore أحيانًا) مكان بديل على نفس الموبايل
    private func storeLogin(_ val: String, forKey key: String) -> Bool {
        Keychain.set(val, forKey: key)
        if Keychain.get(key) == val { return true }
        UD.set(Data(val.utf8).base64EncodedString(), forKey: "fb_\(key)")
        return readLogin(key) == val
    }

    private func readLogin(_ key: String) -> String? {
        if let v = Keychain.get(key), !v.isEmpty { return v }
        if let b = UD.string(forKey: "fb_\(key)"), let d = Data(base64Encoded: b), let s = String(data: d, encoding: .utf8), !s.isEmpty { return s }
        return nil
    }

    func saveLogin(user: String, pass: String) {
        let u = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, !pass.isEmpty else {
            loginStatus = "❌ اكتب اسم المستخدم والباسورد الأول"
            return
        }
        let okU = storeLogin(u, forKey: "loginUser")
        let okP = storeLogin(pass, forKey: "loginPass")
        hasSavedLogin = okU && okP
        autoLoginTries = 0
        autoLoginWindowAt = Date.distantPast
        if hasSavedLogin {
            let where_ = (Keychain.get("loginPass") == pass) ? "الـ Keychain" : "مخزن بديل على الموبايل"
            loginStatus = "✅ الداتا محفوظة (\(where_)) — لو الجلسة قفلت هسجل دخولك لوحدي"
            logActivity("🔐 حفظت بيانات الدخول على الموبايل (\(where_)) — لو طلعت صفحة الدخول هسجلها لوحدي")
        } else {
            loginStatus = "❌ مقدرتش أحفظ على الجهاز ده — جرب تاني"
        }
    }

    func deleteLogin() {
        Keychain.del("loginUser")
        Keychain.del("loginPass")
        UD.removeObject(forKey: "fb_loginUser")
        UD.removeObject(forKey: "fb_loginPass")
        hasSavedLogin = false
        loginStatus = ""
        logActivity("🗑 مسحت بيانات الدخول المحفوظة")
    }

    /// بعد أي تحميل صفحة: الجافاسكريبت هو اللي بيكتشف فورم اللوجين — لو لقيه والداتا محفوظة يسجل لوحك
    /// (3 محاولات/4 دقايق بحد أقصى لو الداتا غلط — ومفيش لوب مفتوح)
    private func tryAutoLogin() {
        guard autoLoginEnabled,
              let u = readLogin("loginUser"), !u.isEmpty,
              let p = readLogin("loginPass"), !p.isEmpty else { return }
        if Date().timeIntervalSince(autoLoginWindowAt) < 240, autoLoginTries >= 3 {
            if !loginStatus.contains("غلط") {
                loginStatus = "❌ جربت 3 مرات ورجعت صفحة الدخول — الغالب الداتا المحفوظة غلط. اكتبها تاني واضغط حفظ"
                logActivity("❌ الدخول التلقائي فشل 3 مرات — حدّث الداتا من كارت حفظ الداتا")
            }
            return
        }
        guard Date().timeIntervalSince(lastAutoLoginAt) > 15 else { return }
        lastAutoLoginAt = Date()
        engine.tryAutoLogin(user: u, pass: p) { [weak self] found, submitted, note in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if found && submitted {
                    if self.autoLoginTries == 0 { self.autoLoginWindowAt = Date() }
                    self.autoLoginTries += 1
                    self.loginStatus = "🔐 سجلت دخولك لوحدي (محاولة \(self.autoLoginTries))..."
                    self.logActivity("🔐 صفحة الدخول ظهرت — بسجل دخولك لوحدي بالداتا المحفوظة (محاولة \(self.autoLoginTries))")
                } else if found {
                    self.loginStatus = "⚠️ لقيت فورم دخول بس مقدرتش أملأه (\(note))"
                    self.logActivity("⚠️ فورم دخول موجود بس الفيل مش مظبوط (\(note))")
                } else {
                    // مش صفحة لوجين = إما إحنا في اللعبة (نجاح!) أو صفحة عادية
                    if self.autoLoginTries != 0 {
                        self.autoLoginTries = 0
                        self.autoLoginWindowAt = Date.distantPast
                        self.loginStatus = "✅ رجعنا للعبة — الدخول التلقائي نجح"
                        self.logActivity("✅ الدخول التلقائي نجح ورجعنا للعبة")
                    }
                }
            }
        }
    }

    // MARK: - مسجل الخطوات (🎬 تسجيل كامل بإيدك): بدء ← امشي خطواتك ← توقف ← زرار تشغيل + مدة
    @Published var recorderArmed = false
    @Published var recorderKind = "farm"          // "farm" أو "retreat"
    @Published var recorderLog = ""               // LOG كامل للخطوات — يننسخ ويتبعتلي
    /// الخطوات المكتشفة لحد الآن (بتتسحب من الصفحة بعد كل تحميل)
    private var recorderDraft: [[String: String]] = []
    var recorderStepCount: Int { recorderDraft.count }
    var farmSteps: [[String: String]] { (UD.array(forKey: "recorderFarmSteps") as? [[String: String]]) ?? [] }
    var recorderFarmStepCount: Int { farmSteps.count }
    var farmRecording: [String: String] { (UD.dictionary(forKey: "farmRecording") as? [String: String]) ?? [:] }
    var retreatRecording: [String: String] { (UD.dictionary(forKey: "retreatRecording") as? [String: String]) ?? [:] }

    private func recLog(_ line: String) {
        recorderLog = (recorderLog + "\n" + "[\(Self.stamp())] \(line)").trimmingCharacters(in: .whitespacesAndNewlines)
        UD.set(recorderLog, forKey: "recorderLog")
    }

    private static func stamp() -> String {
        let df = DateFormatter(); df.dateFormat = "HH:mm:ss"
        return df.string(from: Date())
    }

    private func shortURL(_ u: String) -> String {
        guard let url = URL(string: u) else { return u }
        let path = url.path.isEmpty ? "/" : url.path
        return path + (url.query.map { "?\($0)" } ?? "")
    }

    /// 🎬 بدء التسجيل: امشي في خطواتك عادي ودوس توقف لما تخلص
    func startRecording(_ kind: String) {
        recorderKind = kind
        recorderDraft = []
        engine.armRecording(clear: true) { [weak self] ok in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !ok {
                    self.logActivity("❌ مقدرتش أبدأ التسجيل — جرب تاني")
                    return
                }
                self.recorderArmed = true
                self.recorderLog = "[\(Self.stamp())] 🎬 بدء تسجيل \(kind == "farm" ? "النهب" : "الهروب")"
                self.recLog("ℹ️ كل صفحة تفتحها وكل ضغطة بتتسجل — امشي خطواتك عادي وارجع دوس توقف")
                self.logActivity(kind == "farm"
                    ? "🎬 بدأ تسجيل النهب: امشي في خطواتك عادي (افتح القايمة، علّم الهدافين، دوس إطلاق) ولما تخلص ارجع دوس ⏹ توقف التسجيل"
                    : "🎬 بدأ تسجيل الهروب: اعمله بإيدك مرة (نقطة التجمع ← الكل ← نهب ← الإحداثيات ← موافق) ولما تخلص دوس ⏹ توقف التسجيل")
            }
        }
    }

    /// ⏹ توقف: نسحب آخر الخطوات ونتحفظ بيها
    func stopRecording() {
        drainRecorderSteps(final: true)
    }

    /// سحب الخطوات المتراكمة من الصفحة الحالية (+ تشخيص الخطاب في الـ LOG)
    private func drainRecorderSteps(final: Bool) {
        engine.drainRecorderSteps { [weak self] raw, hookOk, armedOk in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !hookOk { self.recLog("⚠️ الخطاب مش منصب على الصفحة دي (\(self.shortURL(self.webView?.url?.absoluteString ?? "")))") }
                else if !armedOk { self.recLog("⚠️ التسجيل مش مسلّح على الصفحة دي — في مشكلة في التخزين") }
                var added = 0
                for st in raw {
                    var step: [String: String] = [:]
                    for (k, v) in st { step[k] = "\(v)" }
                    guard step["type"] == "post" else { continue }
                    self.recorderDraft.append(step)
                    added += 1
                    let fields = (step["fields"] ?? "").isEmpty ? "" : " — حقول: \(step["fields"] ?? "")"
                    self.recLog("✍️ ضغطة/فورم على \(self.shortURL(step["page"] ?? "")): \(self.shortURL(step["url"] ?? ""))\(fields)")
                }
                if added > 0 { self.logActivity("📝 سجلت \(added) ضغطة جديدة (المجموع \(self.recorderStepCount) خطوة)") }
                if final { self.finishRecording() }
            }
        }
    }

    /// اختيار ضغطة الهروب الحقيقية: آخر فورم فيه x و y و c (مش xhr) — دي ضغطة الإرسال الفعلية
    private func pickRetreatPost(_ posts: [[String: String]]) -> [String: String]? {
        for st in posts.reversed() {
            if st["fields"] == "(xhr)" || st["fields"] == "(fetch)" { continue }
            let b = st["body"] ?? ""
            let hasXY = bodyParam(b, "x") != "?" && bodyParam(b, "y") != "?"
            let hasC = bodyParam(b, "c") != "?" || b.contains("x_token")
            if hasXY && hasC { return st }
        }
        // آخر فرصة: أي فورم فيه x و y
        return posts.reversed().first { bodyParam($0["body"] ?? "", "x") != "?" && bodyParam($0["body"] ?? "", "y") != "?" }
    }

    private func finishRecording() {
        recorderArmed = false
        engine.stopRecording()
        let posts = recorderDraft.filter { $0["type"] == "post" }
        recLog("⏹ توقف التسجيل — \(recorderDraft.count) خطوة (فيهم \(posts.count) ضغطة فورم)")
        guard !recorderDraft.isEmpty else {
            logActivity("⚠️ ما اتسجلش أي خطوة! افتح أي صفحة في اللعبة بعد بدء التسجيل عشان أقدر ألقطها — وأعد المحاولة")
            return
        }
        if recorderKind == "farm" {
            // كل الخطوات (صفحات + ضغطات) — إعادة التشغيل بتمشي بيها بالترتيب زي خطواتك بالظبط
            UD.set(recorderDraft, forKey: "recorderFarmSteps")
            if let last = posts.last {
                UD.set(["url": last["url"] ?? "", "body": last["body"] ?? ""], forKey: "farmRecording")
            }
            nextFarmAt = Date().addingTimeInterval(45)
            recLog("💾 اتحفظت خطوات النهب: \(recorderDraft.count) خطوة (\(posts.count) فورم + \(recorderDraft.count - posts.count) صفحة)")
            logActivity("✅ تسجيل النهب تمام (\(recorderDraft.count) خطوة)! دوس 🚀 ابدأ النهب دلوقتي — أو هيشتغل لوحده كل \(farmIntervalMin) دقيقة")
        } else if let last = pickRetreatPost(posts) {
            UD.set(["url": last["url"] ?? "", "body": last["body"] ?? ""], forKey: "retreatRecording")
            let x = bodyParam(last["body"] ?? "", "x")
            let y = bodyParam(last["body"] ?? "", "y")
            let c = bodyParam(last["body"] ?? "", "c")
            let w = c == "2" ? "تعزيز" : (c == "3" ? "هجوم" : "نهب")
            recLog("💾 اتحفظ الهروب لـ (\(x)|\(y)) بوضع \(w) (من فورم فيه x/y/c)")
            logActivity("✅ تسجيل الهروب تمام لـ (\(x)|\(y)) بوضع \(w) — أول هجوم حقيقي هيكرره بجنود القرية الحاليين")
        } else {
            recLog("⚠️ الهروب: مفيش ضغطة فورم (a2b) — آخر خطوة: \(recorderDraft.last?["page"] ?? "-")")
            logActivity("⚠️ ما لقيتش ضغطة الهروب — لازم آخر خطوة تكون ضغط موافق في صفحة إرسال القوات (نقطة التجمع ← نهب ← موافق). أعد التسجيل وابعتلي الـ LOG لو عدت تاني")
        }
    }

    /// بيندها بعد كل تحميل صفحة: إعادة تسليح + خطوة "فتحت صفحة" + سحب أي ضغطات جديدة
    /// (على سيرفر أغلب خطوات النهب روابط وتنقلات GET — فالتسجيل بيحفظ كل صفحة انت فتحتها كخطوة)
    func recorderPageLoaded() {
        guard recorderArmed else { return }
        engine.armRecording(clear: false) { _ in }
        let href = webView?.url?.absoluteString ?? ""
        // تنقل البوت نفسه (تجسس/تدريب) مايتسجلش — تسجيل المستخدم بس
        let isBotNav = Date().timeIntervalSince(lastBotNavAt) < 3
        if !href.isEmpty && !isBotNav {
            if let last = recorderDraft.last, last["type"] == "nav", last["page"] == href {
                // نفس الصفحة — من غير تكرار
            } else {
                recorderDraft.append(["type": "nav", "page": href])
                recLog("📄 فتحت (\(recorderDraft.count)): \(shortURL(href))")
            }
        }
        drainRecorderSteps(final: false)
    }

    /// 📋 نسخ LOG التسجيل (يبعتلي إياه أظبطه لو فيه مشكلة)
    func copyRecorderLog() {
        UIPasteboard.general.string = recorderLog
        logActivity("📋 اتنسخ LOG التسجيل — الصقه في المحادثة")
    }

    // MARK: - إعادة تشغيل خطوات النهب المسجلة (بالتسلسل: افتح صفحة الخطوة ← ابعت الضغطة ← اللي بعدها)
    private var replaySteps: [[String: String]] = []
    private var replayIdx = 0
    private var replayBusy = false
    private var pendingReplayAfterLoad = false
    private var replayRetries = 0

    private func runFarmCycleFallbackNav() {
        if pageKind == "farmlist" {
            doFarmLaunch()
        } else {
            farmInfoShown = false
            logActivity("🏴 ماشي لقايمة النهب... (نصيحة: سجّل النهب بإيدك مرة — الأضمن بكتير)")
            navigate(path: "build.php?gid=16&t=99")
        }
    }

    /// 🚀 تشغيل خطوات النهب المسجلة (صفحات + ضغطات — بالترتيب زي خطواتك)
    func startFarmStepsReplay(auto: Bool) {
        let steps = farmSteps
        guard !steps.isEmpty else {
            if !farmRecording.isEmpty {
                doFarmReplay()
            } else if auto {
                runFarmCycleFallbackNav()
            } else {
                logActivity("⚠️ مفيش خطوات مسجلة — دوس 🔴 بدء تسجيل النهب الأول")
            }
            return
        }
        guard !replayBusy else { return }
        replaySteps = steps
        replayIdx = 0
        replayRetries = 0
        replayBusy = true
        recLog(auto ? "▶️ تشغيل تلقائي لخطوات النهب (\(steps.count) خطوة)" : "▶️ تشغيل يدوي لخطوات النهب (\(steps.count) خطوة)")
        logActivity(auto ? "🏴 وقت النهب — بشغل خطواتك المسجلة (\(steps.count) خطوة)..." : "🚀 بشغل خطواتك المسجلة دلوقتي...")
        runNextReplayStep()
    }

    private func samePage(_ page: String) -> Bool {
        guard let cur = webView?.url else { return false }
        guard let target = URL(string: page) else { return false }
        return cur.path == target.path && (cur.query ?? "") == (target.query ?? "")
    }

    /// تنقل مطلق (رابط كامل) — للتشغيل اللي المستخدم ضغطه بنفسه
    private func navigateAbs(_ url: String) {
        guard let u = URL(string: url) else { return }
        lastBotNavAt = Date()
        webView?.load(URLRequest(url: u))
    }

    private func runNextReplayStep() {
        guard replayIdx < replaySteps.count else {
            replayBusy = false
            markSubmitBusy()
            nextFarmAt = Date().addingTimeInterval(TimeInterval(farmIntervalMin * 60))
            recLog("✅ كل خطوات النهب اشتغلت")
            logActivity("🏴 خطوات النهب اشتغلت كلها ✅ — الجاية بعد \(farmIntervalMin) دقيقة")
            return
        }
        let st = replaySteps[replayIdx]
        let page = st["page"] ?? ""
        // خطوة "فتح صفحة" (رابط/تنقل GET): بنروح للصفحة نفسها وبس
        if st["type"] == "nav" {
            recLog("📄 خطوة \(replayIdx + 1)/\(replaySteps.count): فتح \(shortURL(page))")
            replayIdx += 1
            pendingReplayAfterLoad = true
            navigateAbs(page)
            return
        }
        if !samePage(page) {
            pendingReplayAfterLoad = true
            navigateAbs(page)
            return
        }
        markSubmitBusy()
        engine.replayRecordedPost(saved: st) { [weak self] ok, msg in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if msg == "__pending__" {
                    self.replayRetries += 1
                    if self.replayRetries > 2 {
                        self.recLog("⚠️ ضغطة \(self.replayIdx + 1) مفيش منها رد — بنكمل")
                        self.replayIdx += 1
                        self.replayRetries = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { self.runNextReplayStep() }
                    return
                }
                self.recLog("\(ok ? "✅" : "❌") ضغطة \(self.replayIdx + 1)/\(self.replaySteps.count): \(msg)")
                if !ok && msg.contains("لوجين") {
                    self.replayBusy = false
                    self.logActivity("❌ الجلسة انقطعت أثناء النهب — أول ما تسجل دخول هيكمل عادي")
                    return
                }
                self.replayIdx += 1
                self.replayRetries = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { self.runNextReplayStep() }
            }
        }
    }

    /// قراية متغير من جسم POST المُشفّر (x=..&y=..)
    private func bodyParam(_ body: String, _ key: String) -> String {
        for kv in body.split(separator: "&") {
            let p = kv.split(separator: "=", maxSplits: 1).map(String.init)
            if p.count == 2, p[0] == key { return p[1] }
        }
        return "?"
    }

    /// أدق مهمة تدريب معلقة — النظام عمره ما ينسى التدريب حتى مع فترات الهدوء
    private func ensureTrainQueued(withinMinutes mi: Int) {
        let next = Date().addingTimeInterval(TimeInterval(mi * 60))
        if nextQueuedTrainAt < Date() || next < nextQueuedTrainAt {
            nextQueuedTrainAt = next
        }
    }
    /// خلايا الخريطة اللي البوت زارها (dorf3?id=) — عشان ما يزورش نفس الخلية تاني
    private var exploredCells = Set<String>()
    private var lastExploreAt = Date.distantPast
    private var karteFruitless = 0
    private var lastRecordedAt = Date.distantPast
    /// نافذة هدوء بعد أي إرسال: بنمنع أي تنقل من البوت 8 ثواني عشان ما نلغيش الـ POST وهو طاير
    private var submitQuietUntil = Date.distantPast

    private func markSubmitBusy() {
        submitQuietUntil = Date().addingTimeInterval(8)
    }
    private var lastRecordedURL = ""

    /// سجل كل حركة بيعملها المحرك — بيظهر في البانل وبيساعدنا نعرف مين اللي فشل وليه.
    func logActivity(_ text: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        DispatchQueue.main.async {
            self.activityLog.insert("[\(f.string(from: Date()))] \(text)", at: 0)
            if self.activityLog.count > 40 {
                self.activityLog.removeLast(self.activityLog.count - 40)
            }
        }
    }

    var webView: WKWebView?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    let gameURL = "https://utatar.com/sign"
    
    override init() {
        super.init()
        // استرجاع الإعدادات المحفوظة وإعادة تشغيل الأوتوماتك لو كان شغّال
        autoCollectResources = UD.bool(forKey: "autoCollect")
        autoBuildQueue = UD.bool(forKey: "autoBuild")
        autoSpyEnabled = UD.bool(forKey: "autoSpy")
        autoLoginEnabled = UD.object(forKey: "autoLogin") == nil ? true : UD.bool(forKey: "autoLogin")
        hasSavedLogin = (readLogin("loginPass") != nil)
        recorderLog = UD.string(forKey: "recorderLog") ?? ""
        autoTrainCount = UD.object(forKey: "autoTrainCount") == nil ? 10 : UD.integer(forKey: "autoTrainCount")
        autoAttackCount = UD.object(forKey: "autoAttackCount") == nil ? 50 : UD.integer(forKey: "autoAttackCount")
        autoRetreatEnabled = UD.bool(forKey: "autoRetreat")
        retreatX = UD.integer(forKey: "retreatX")
        retreatY = UD.integer(forKey: "retreatY")
        manualSpyX = UD.string(forKey: "manualSpyX") ?? ""
        manualSpyY = UD.string(forKey: "manualSpyY") ?? ""
        trainCounts = (UD.dictionary(forKey: "trainCounts") as? [String: String]) ?? [:]
        attackAlerts = UD.object(forKey: "attackAlerts") == nil ? true : UD.bool(forKey: "attackAlerts")
        resourceFullAlerts = UD.object(forKey: "resFullAlerts") == nil ? true : UD.bool(forKey: "resFullAlerts")
        buildCompleteAlerts = UD.object(forKey: "buildAlerts") == nil ? true : UD.bool(forKey: "buildAlerts")
        if UD.bool(forKey: "autoTrain") {
            autoTrainTroops = true
        }
        if UD.bool(forKey: "automationOn") {
            isAutomationEnabled = true
            logActivity("♻️ رجعنا — الأوتوماتك شغّال تاني من حيث وقف")
        }
        pageRecords = UD.string(forKey: "pageRecords") ?? ""
        barracksPath = UD.string(forKey: "barracksPath") ?? ""
        savedTroopTypes = (UD.array(forKey: "savedTroopTypes") as? [[String: Any]]) ?? []
        lastTrainPost = (UD.dictionary(forKey: "lastTrainPost") as? [String: String]) ?? [:]
        alertStatus = UD.string(forKey: "alertStatus") ?? ""
        autoFarmEnabled = UD.bool(forKey: "autoFarmEnabled")
        farmIntervalMin = UD.object(forKey: "farmIntervalMin") == nil ? 30 : max(5, UD.integer(forKey: "farmIntervalMin"))
        trainIntervalMin = UD.object(forKey: "trainIntervalMin") == nil ? 10 : max(1, UD.integer(forKey: "trainIntervalMin"))
        setupTimer()
        setupLifecycleWatchers()
        if isAutomationEnabled {
            UIApplication.shared.isIdleTimerDisabled = true
            KeepAlive.shared.start()
        }
    }
    
    func setupWebView(_ webView: WKWebView) {
        self.webView = webView
        loadGame()
    }
    
    func loadGame() {
        guard let url = URL(string: gameURL) else { return }
        let request = URLRequest(url: url)
        webView?.load(request)
    }
    
    func refresh() {
        webView?.reload()
    }
    
    func goBack() {
        webView?.goBack()
    }
    
    func goForward() {
        webView?.goForward()
    }
    
    // MARK: - Automation
    
    func toggleAutomation() {
        isAutomationEnabled.toggle()
        UD.set(isAutomationEnabled, forKey: "automationOn")
        UIApplication.shared.isIdleTimerDisabled = isAutomationEnabled
        if isAutomationEnabled {
            startAutomation()
            KeepAlive.shared.start()
            sendNotification(title: "أوتوماتك شغّال", body: "المساعد شغّال دلوقتي 🎮 — ويفضل شغال في الخلفية")
        } else {
            stopAutomation()
            KeepAlive.shared.stop()
            sendNotification(title: "أوتوماتك واقف", body: "المساعد الأوتوماتك اتقفل")
        }
    }
    
    /// مراقبة حياة التطبيق: منع قفل الشاشة + إعادة تشغيل البوت أول ما يرجع
    private func setupLifecycleWatchers() {
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.isAutomationEnabled else { return }
            KeepAlive.shared.start()
            UIApplication.shared.isIdleTimerDisabled = true
            self.runAutomationCycle()
            self.logActivity("♻️ رجع التطبيق للقدام — الأوتوماتك شغال")
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.isAutomationEnabled else { return }
            KeepAlive.shared.start()   // نتأكد إن الصوت الصامت شغال قبل ما نتحجب
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            UD.set(true, forKey: "automationOn")   // نفتكر إن الأوتوماتك كان شغال
            _ = self.isAutomationEnabled
        }
    }

    private func setupTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self = self, self.isAutomationEnabled else { return }
            self.runAutomationCycle()
        }
    }
    
    private func startAutomation() {
        runAutomationCycle()
    }
    
    private func stopAutomation() {
        // Automation stopped
    }
    
    private func runAutomationCycle() {
        // تسجيل شغال؟ البوت كله يوقف — تسجيل المستخدم بس (مفيش تنقلات بوت تلوث التسجيل)
        if recorderArmed {
            drainRecorderSteps(final: false)
            return
        }
        // إعادة خطوات النهب شغالة؟ محدش يتحرك غيرها
        guard !replayBusy, !pendingReplayAfterLoad else { return }
        // Collect game state
        collectGameState()
        refreshGameData()
        advancePendingAction()
        // لو في إرسال لسه طاير — بنستنى ونسيب باقي الأ-shغل للدورة الجاية
        guard Date() >= submitQuietUntil else { return }
        // Run enabled automations
        if autoCollectResources {
            injectAutoCollect()
        }
        if autoBuildQueue {
            injectAutoBuild()
        }
        if autoTrainTroops {
            // نبّاه لو المهمة المعلقة فات وقتها (الجهاز نام/الشبكة قطعت): أقرب فرصة تتدرب
            if nextQueuedTrainAt < Date().addingTimeInterval(-10 * 60) {
                nextQueuedTrainAt = Date()
            }
            injectAutoTrain()
        }
        if attackAlerts || autoRetreatEnabled {
            checkAlerts()
        }
        if resourceFullAlerts {
            checkResourcesFull()
        }
        if autoSpyEnabled {
            exploreAndSpy()
        }
        if autoFarmEnabled {
            runFarmCycle()
        }
        checkAlerts()
    }

    /// نهب تلقائي من قائمة النهب: كل فترة بيطلق القايمة (الخادم بيبعت أقل من المتاح لوحده)
    private func runFarmCycle() {
        guard pendingAction == nil, Date() >= submitQuietUntil else { return }
        guard Date() >= nextFarmAt else {
            if !farmInfoShown {
                farmInfoShown = true
                let mins = max(1, Int(((nextFarmAt.timeIntervalSinceNow) / 60.0).rounded(.up)))
                logActivity("🏴 النهب الجاي بعد \(mins) دقيقة")
            }
            return
        }
        // الأضمن: خطوات النهب المسجلة بإيد المستخدم — بنشغلها بالتسلسل
        if recorderFarmStepCount > 0 {
            startFarmStepsReplay(auto: true)
            return
        }
        if !farmRecording.isEmpty {
            doFarmReplay()
            return
        }
        runFarmCycleFallbackNav()
    }

    /// إطلاق الضغطة المسجلة (نفس action المستخدم) — من أي صفحة، بدون تنقل
    private func doFarmReplay() {
        engine.replayRecordedPost(saved: farmRecording) { [weak self] ok, msg in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if msg == "__pending__" { return }
                if ok {
                    self.markSubmitBusy()
                    self.nextFarmAt = Date().addingTimeInterval(TimeInterval(self.farmIntervalMin * 60))
                    self.logActivity("🏴 \(msg) — الجاية بعد \(self.farmIntervalMin) دقيقة ✅")
                } else {
                    self.nextFarmAt = Date().addingTimeInterval(300)
                    self.logActivity("⚠️ إعادة الضغطة المسجلة فشلت (\(msg)) — هجرب تاني بعد 5 دقايق (لو فضلت فاشلة: أعد تسجيل النهب)")
                }
            }
        }
    }

    private func doFarmLaunch() {
        engine.launchFarmList { [weak self] ok, msg in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if ok {
                    // الإرسال الأصلي بينقل الصفحة — نعلمه زي أي تنقل بوت + هدوء للطلب اللي طاير
                    self.lastBotNavAt = Date()
                    self.markSubmitBusy()
                    self.nextFarmAt = Date().addingTimeInterval(TimeInterval(self.farmIntervalMin * 60))
                    self.logActivity("🏴 \(msg) — الجاية بعد \(self.farmIntervalMin) دقيقة ✅")
                } else {
                    self.nextFarmAt = Date().addingTimeInterval(300)
                    self.logActivity("⚠️ \(msg) — هجرب تاني بعد 5 دقايق")
                }
            }
        }
    }

    /// 🏴 إطلاق فوري (زرار التجربة)
    func testFarmLaunch() {
        if recorderFarmStepCount > 0 {
            startFarmStepsReplay(auto: false)
            return
        }
        if !farmRecording.isEmpty {
            logActivity("🏴 هطلق ضغطفك المسجلة حالاً (من غير ما أفتح أي صفحة)...")
            doFarmReplay()
            return
        }
        guard pageKind == "farmlist" else {
            logActivity("🏴 مفيش تسجيل — دوس 🔴 بدء تسجيل النهب واعمل خطواتك مرة واحدة")
            return
        }
        doFarmLaunch()
    }

    /// التجسس التلقائي: كل دورة تجسس للقرية اللي بعد الحالي (دورياً).
    private var spyCursor = 0
    /// القرى/الخلايا اللي اتعلمنا عليها في الجلسة دي — ما نرجعش لها تاني على طول.
    private var spyDone = Set<String>()

    /// مستكشف الخريطة + التجسس الذكي:
    /// 1) أي قرية معلومة (لها لاعب وإحداثيات) → تجسس فوري.
    /// 2) مفيش؟ يزور خلية خريطة جديدة (dorf3?id=) كل 25 ثانية ويتعرف عليها.
    /// 3) خلصت الخلايا؟ يجيب منطقة جديدة من الخريطة (مرتين كحد أقصى).
    private func exploreAndSpy() {
        guard pendingAction == nil, Date() >= submitQuietUntil else { return }
        // 1) قرى معروفة الإحداثيات واللاعب
        for _ in 0..<mapVillages.count {
            spyCursor = (spyCursor + 1) % mapVillages.count
            let v = mapVillages[spyCursor]
            guard v.x != 0 || v.y != 0 else { continue }
            guard !spyDone.contains(v.id) else { continue }
            let nm = v.name
            if nm.contains("واحة") || nm.contains("مجهول") || nm.contains("خالية") { continue }
            let pl = v.player.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pl.isEmpty, pl != "-", pl != "?" else { continue }
            spyDone.insert(v.id)
            logActivity("🤖 تجسس تلقائي على: \(v.name) (\(v.x)|\(v.y)) لاعب: \(v.player)")
            startSpy(x: v.x, y: v.y, name: v.name)
            return
        }
        // 2) استكشاف خلية جديدة من خلايا الخريطة اللي مسحناها
        guard Date().timeIntervalSince(lastExploreAt) > 25 else { return }
        let cell = mapVillages.first { v in
            v.href.contains("dorf3?id=") && !exploredCells.contains(v.id)
        }
        if let cell = cell {
            exploredCells.insert(cell.id)
            lastExploreAt = Date()
            logActivity("🧭 استكشاف الخريطة: خلية جديدة (كشفنا \(exploredCells.count))")
            navigate(path: "/" + cell.href)
            return
        }
        // 3) الخلايا خلصت — نجيب منطقة خريطة جديدة (من غير لوب مفتوح)
        if pageKind != "map", karteFruitless < 2, Date().timeIntervalSince(lastExploreAt) > 90 {
            lastExploreAt = Date()
            logActivity("🧭 رايح أجيب منطقة جديدة من الخريطة")
            navigate(path: "/karte")
        }
    }

    // MARK: - القراءة الحقيقية من اللعبة (GameEngine)

    /// بيشتغل بعد كل تحميل صفحة وكل دورة أوتوماتك:
    /// بيقرا الموارد والجنود والوحدات القابلة للتدريب من الـ DOM الحقيقي.
    func refreshGameData() {
        guard let urlString = webView?.url?.absoluteString else { return }
        let kind = GameEngine.pageKind(from: urlString)
        pageKind = kind
        recordCurrentPageIfNeeded()

        engine.readResources { [weak self] res in
            guard let self = self, let res = res else { return }
            DispatchQueue.main.async {
                self.gameResources = res
                self.woodAmount = "\(res.wood)"
                self.clayAmount = "\(res.clay)"
                self.ironAmount = "\(res.iron)"
                self.wheatAmount = "\(res.crop)"
                self.wheatProduction = "\(res.cropProd)"
            }
        }

        // الجنود الموجودين في القرية (نقطة التجمع / صفحات القرية)
        engine.readHomeTroops { [weak self] units in
            guard let self = self else { return }
            DispatchQueue.main.async {
                // الحقيقة الحقيقية: اللي اللعبة قالت صفر يبقى صفر (اللي مشي مش هيبقى موجود!)
                self.homeTroops = units.map { u in
                    var u = u
                    if u.name.isEmpty { u.name = GameEngine.arabicUnitName(u.id) }
                    return u
                }
            }
        }

        // الوحدات القابلة للتدريب — نفحصها في أي صفحة (الثكنات ممكن يكون رابطها مختلف)
        engine.readTrainableUnits { [weak self] units in
            guard let self = self else { return }
            DispatchQueue.main.async {
                // السجل بيهم بس صفحات المباني (في أي صفحة تانية القراءة ملهاش معنى وبتلخبط)
                if kind == "build", units.count != self.trainableUnits.count {
                    self.logActivity(units.isEmpty
                        ? "مفيش وحدات تدريب في الصفحة (\(kind))"
                        : "لقيت \(units.count) وحدة قابلة للتدريب في \(kind)")
                }
                // لقينا فورمة تدريب في صفحة build؟ سجّل عنوانها — دي الثكنة/الإسطبل اللي بندرّب فيها
                if !units.isEmpty, kind == "build", let url = self.webView?.url {
                    self.barracksPath = Self.trainablePath(from: url)
                }
                // اللقط الدائم: أي أنواع جديدة تظهر → تتخزن للأبد
                self.captureTroopTypes(units)
                // قايمة العرض ما تتفضيش غير من صفحة مبنى فعلًا — الصفحات التانية ما تمسحهاش
                if !units.isEmpty || kind == "build" {
                    self.trainableUnits = units
                }
            }
        }

        if kind == "map" {
            scanMap()
        }

        if kind == "reports" {
            engine.readSpyReports { [weak self] reps in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.spyReports = reps
                }
            }
        }
    }

    /// مسح الخريطة الحقيقية وجمع القرى.
    func scanMap() {
        guard !isScanningMap else { return }
        isScanningMap = true
        engine.scanMapVillages { [weak self] villages in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if !villages.isEmpty {
                    let old = Dictionary(self.mapVillages.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                    self.mapVillages = villages.map { v in
                        if let prev = old[v.id], v.name.isEmpty { return prev }
                        return v
                    }
                    // لقينا خلايا جديدة مش متكشفة؟ لو لأ، منعودش للخريطة على الفاضي
                    let fresh = villages.contains { v in v.href.contains("dorf3?id=") && !self.exploredCells.contains(v.id) }
                    self.karteFruitless = fresh ? 0 : min(self.karteFruitless + 1, 3)
                }
                self.isScanningMap = false
                if self.mapVillages.isEmpty {
                    self.gameLog = "افتح صفحة الخريطة عشان أمسح القرى"
                    self.logActivity("🗺️ مفيش قرى — الصفحة دي مش الخريطة أو شكلها مختلف")
                } else {
                    self.gameLog = "لقينا \(self.mapVillages.count) قرية على الخريطة"
                    self.logActivity("🗺️ لقينا \(self.mapVillages.count) قرية")
                }
            }
        }
    }

    /// إرسال جواسيس لإحداثيات — يفتح a2b ويكمل لوحده.
    func startSpy(x: Int, y: Int, name: String) {
        guard x != 0 || y != 0 else {
            logActivity("❌ محتاج إحداثيات (x|y) للتجسس")
            return
        }
        pendingAction = .spy(x: x, y: y, name: name)
        actionStartedAt = Date()
        logActivity("🕵️ تجهيز غزو الكشاف لـ \(name) (\(x)|\(y)) — فاتح نقطة التجمع...")
        navigateToRallyPoint()
    }

    /// هجوم بإحداثيات — يفتح a2b ويبعت العدد المحدد من أول وحدة قتالية.
    func startAttack(x: Int, y: Int, name: String) {
        pendingAction = .attack(x: x, y: y, name: name)
        actionStartedAt = Date()
        logActivity("⚔️ تجهيز هجوم على \(name) (\(x)|\(y)) بعدد \(autoAttackCount) — فاتح نقطة التجمع...")
        navigateToRallyPoint()
    }

    /// الهروب: بكل الجنود لوجهة الهروب (تعزيز).
    /// هدف الهروب: من ضغطة المستخدم المسجلة (x/y/c) أو الإحداثيات المكتوبة + نهب كوضع افتراضي
    private var retreatTarget: (Int, Int, Int) {
        let rec = retreatRecording
        if !rec.isEmpty {
            let x = Int(bodyParam(rec["body"] ?? "", "x")) ?? 0
            let y = Int(bodyParam(rec["body"] ?? "", "y")) ?? 0
            let c = bodyParam(rec["body"] ?? "", "c")
            // من محرك اللعبة: c=2 تعزيز — c=3 هجوم — c=4 نهب → أرقام sendTroops: 1/2/3
            let mode = c == "2" ? 1 : (c == "3" ? 2 : 3)
            if x != 0 || y != 0 { return (x, y, mode) }
        }
        return (retreatX, retreatY, 3)  // نهب — زي ما طلبت: الخيار هجوم للنهب
    }

    func startRetreat(auto: Bool) {
        let troops = homeTroops.filter { $0.count > 0 }
        guard !troops.isEmpty else {
            logActivity("❌ الهروب: مفيش جنود موجودين حالياً (كل اللي عندك في سكة) — أو لازم تفتح القرية الأول عشان أقرا الجنود")
            return
        }
        let (tx, ty, tmode) = retreatTarget
        guard tx != 0 || ty != 0 else {
            logActivity("❌ الهروب: سجّل الهروب بإيدك مرة (الزرار الأحمر) أو اكتب إحداثيات واحة الهروب")
            return
        }
        pendingAction = .retreat
        actionStartedAt = Date()
        let modeName = tmode == 3 ? "نهب" : (tmode == 2 ? "هجوم" : "تعزيز")
        logActivity(auto ? "🏃 إنذار! بجهز الهروب بكل الجنود لـ (\(tx)|\(ty)) بوضع \(modeName)..." : "🏃 تجهيز هروب تجريبي لـ (\(tx)|\(ty)) بوضع \(modeName)...")
        navigateToRallyPoint()
    }

    private func navigateToRallyPoint() {
        guard let url = URL(string: "https://utatar.com/a2b") else { return }
        lastBotNavAt = Date()
        webView?.load(URLRequest(url: url))
        markSubmitBusy()
    }

    /// بيتم ناداه بعد ما أي صفحة تخلص تحميل — قراءة + تنفيذ المهمة المعلقة.
    func handlePageLoaded() {
        // لو الجلسة قفلت وطلعت صفحة الدخول: سجل لوحك فورًا بالداتا المحفوظة
        tryAutoLogin()
        // مسجل الخطوات شغال؟ سجل الصفحة واسحب أي ضغطات جديدة
        recorderPageLoaded()
        // إعادة تشغيل خطوات مستنية تحميل الصفحة
        if pendingReplayAfterLoad {
            pendingReplayAfterLoad = false
            runNextReplayStep()
        }
        // فحص تنبيه فوري بعد أي تحميل صفحة (مكمل للتايمر — الهجوم ما يعديش علينا)
        if attackAlerts || autoRetreatEnabled, Date().timeIntervalSince(lastAlertLoadCheck) > 6 {
            lastAlertLoadCheck = Date()
            checkAlerts()
        }
        refreshGameData()
        advancePendingAction()
        recordCurrentPageIfNeeded()
        // خطافات التسجيل (تدريب + المسجل العام) + قراية أي ضغطة المستخدم سجلها للتو
        engine.installTrainSubmitHook()
        engine.readTrainPost { [weak self] post in
            guard let self = self, let post = post, !post["body", default: ""].isEmpty else { return }
            // حماية مضاعفة: أي ضغطة من صفحة القوات (a2b) مش تدريب — نتجاهلها نهائيًا
            if (post["url"] ?? "").contains("a2b") { return }
            DispatchQueue.main.async {
                let changed = self.lastTrainPost["body"] != post["body"]
                self.lastTrainPost = post
                if changed {
                    self.barracksHintShown = false
                    self.logActivity("✅ سجلت ضغطة التدريب بتاعتك (\(post["url"] ?? "")) — هعيد زيها كل فترة من غير ما تفتح الثكنة")
                }
            }
        }
        // البوت وصل لصفحة مبنية بعد تنقل هو نفسه عمله؟ يدرب حالا (من غير انتظار الفترة)
        if isAutomationEnabled, autoTrainTroops, pendingAction == nil, pageKind == "build",
           Date().timeIntervalSince(lastBotNavAt) < 20 {
            injectAutoTrain(force: true)
        }
        // البوت وصل لقايمة النهب بعد تنقله هو؟ أطلق على طول
        if isAutomationEnabled, autoFarmEnabled, pendingAction == nil, pageKind == "farmlist",
           Date().timeIntervalSince(lastBotNavAt) < 20 {
            doFarmLaunch()
        }
        // البوت زار خلية خريطة (dorf3?id=)؟ نتعرف عليها: فيها لاعب؟ نتجسسها. فاضية؟ نكمل.
        if isAutomationEnabled, autoSpyEnabled, pendingAction == nil,
           pageKind == "villageInfo", Date().timeIntervalSince(lastExploreAt) < 30 {
            processExploredCell()
        }
    }

    /// قراءة صفحة معلومات القرية اللي البوت وصلها من الاستكشاف.
    private func processExploredCell() {
        lastExploreAt = Date()
        guard let urlStr = webView?.url?.absoluteString else { return }
        let vid = urlStr.contains("id=") ? (urlStr.components(separatedBy: "id=").last ?? "") : UUID().uuidString
        engine.readVillageInfo { [weak self] info in
            guard let self = self, let info = info else { return }
            DispatchQueue.main.async {
                let player = ((info["player"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let x = (info["x"] as? Int) ?? 0
                let y = (info["y"] as? Int) ?? 0
                let nm = ((info["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                // حدّث بيانات الخلية في قايمة القرى
                if let idx = self.mapVillages.firstIndex(where: { $0.id == vid }) {
                    let old = self.mapVillages[idx]
                    self.mapVillages[idx] = MapVillage(id: old.id,
                                                       name: nm.isEmpty ? old.name : nm,
                                                       x: x != 0 ? x : old.x,
                                                       y: y != 0 ? y : old.y,
                                                       player: player.isEmpty ? old.player : player,
                                                       population: old.population,
                                                       href: old.href)
                }
                let pl = player.trimmingCharacters(in: .whitespacesAndNewlines)
                if (x != 0 || y != 0), !pl.isEmpty, pl != "-", pl != "?" {
                    guard !self.spyDone.contains(vid) else { return }
                    self.spyDone.insert(vid)
                    self.logActivity("🎯 لقينا قرية لاعب: \(nm) (\(x)|\(y)) — بتجسسها")
                    self.startSpy(x: x, y: y, name: nm.isEmpty ? "قرية" : nm)
                } else {
                    self.logActivity("🧭 الخلية فاضية (مفيش لاعب) — نكمل الاستكشاف")
                }
            }
        }
    }

    /// مسجل الصفحات الأوتوماتيكي: يسجل كل صفحة جديدة (بدون تكرار) عشان نحلل الـ DOM الحقيقي.
    func recordCurrentPageIfNeeded() {
        guard let url = webView?.url?.absoluteString else { return }
        let base = url.components(separatedBy: "#").first ?? url
        let lastBase = lastRecordedURL.components(separatedBy: "#").first ?? lastRecordedURL
        if base == lastBase {
            // نفس الصفحة؟ نسجلها تاني كل 10 دقايق بس (عشان نشوف تغيّر الفورم بعد التدريب)
            guard Date().timeIntervalSince(lastRecordedAt) > 600 else { return }
        }
        lastRecordedURL = url
        lastRecordedAt = Date()
        engine.runPageRecord { [weak self] text in
            guard let self = self, !text.isEmpty else { return }
            DispatchQueue.main.async {
                let sep = self.pageRecords.isEmpty ? "" : "\n──── صفحة جديدة ──────\n"
                var buf = self.pageRecords + sep + text
                if buf.count > 9000 {
                    buf = String(buf.suffix(9000))
                }
                self.pageRecords = buf
            }
        }
    }

    /// تنفيذ المهمة المعلقة لما نكون على صفحة إرسال الجنود.
    private func advancePendingAction() {
        guard let action = pendingAction else { return }
        guard pageKind == "a2b" else {
            // مهلة 15 ثانية: لو صفحة a2b ما فتحتش نلغي
            if Date().timeIntervalSince(actionStartedAt) > 15 {
                pendingAction = nil
                logActivity("⏱️ صفحة نقطة التجمع ما فتحتش — اتلغت المهمة")
            }
            return
        }
        switch action {
        case .spy(let x, let y, let name):
            pendingAction = nil
            engine.sendTroops(x: x, y: y, units: [(14, 3)], mode: 3) { [weak self] ok, msg in
                DispatchQueue.main.async {
                    self?.logActivity(ok ? "✅ \(msg) — تجسس \(name) (\(x)|\(y)). التقرير في berichte" : "❌ التجسس فشل: \(msg)")
                    if ok {
                        self?.sendNotification(title: "🕵️ تجسس", body: "الكشاف في الطريق لـ \(name)")
                    }
                }
            }
        case .attack(let x, let y, let name):
            pendingAction = nil
            engine.sendTroops(x: x, y: y, units: [(11, autoAttackCount)], mode: 2) { [weak self] ok, msg in
                DispatchQueue.main.async {
                    self?.logActivity(ok ? "⚔️ \(msg) — هجوم على \(name) (\(x)|\(y))" : "❌ الهجوم فشل: \(msg)")
                    if ok {
                        self?.sendNotification(title: "⚔️ هجوم", body: "القوات في الطريق لـ \(name)")
                    }
                }
            }
        case .retreat:
            pendingAction = nil
            let pairs = homeTroops.filter { $0.count > 0 }.map { ($0.id, $0.count) }
            if pairs.isEmpty {
                logActivity("❌ الهروب اتلغي: القرية فاضية (الجنود كلها في سكة)")
                return
            }
            let (sx, sy, smode) = retreatTarget
            logActivity("🏃 ببعت \(pairs.map { "\($0.1)×u\($0.0)" }.joined(separator: " + "))...")
            engine.sendTroops(x: sx, y: sy, units: pairs, mode: smode) { [weak self] ok, msg in
                DispatchQueue.main.async {
                    self?.logActivity(ok ? "🏃 \(msg) — الهروب انطلق لـ (\(sx)|\(sy))" : "❌ الهروب فشل: \(msg)")
                    if ok {
                        self?.sendNotification(title: "🏃 هروب", body: "الجنود في الطريق لوجهة الهروب")
                    }
                }
            }
        }
    }

    /// فحص إنذار الهجوم (بيشتغل على صفحات القرية بس) + الهروب التلقائي.
    private func checkAlerts() {
        guard pendingAction == nil, attackAlerts || autoRetreatEnabled else { return }
        engine.readAlert { [weak self] incoming, hits, hasMov, moves in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if incoming {
                    self.alertStatus = "🚨 هجوم قادم! (\(hits.joined(separator: "، ")))"
                    // إشعار كل 5 دقايق على الأكثر عشان ميبقاش سبام
                    if Date().timeIntervalSince(self.lastAlertNotifyAt) > 300 {
                        self.lastAlertNotifyAt = Date()
                        self.logActivity("🚨 هجوم جاي على القرية! (\(hits.joined(separator: "، "))) — راجع صفحة التحركات حالاً")
                        self.sendNotification(title: "🚨 هجوم قادم!", body: "البوت رصد علامة الهجوم في التحركات — افتح اللعبة حالاً")
                    }
                    if self.autoRetreatEnabled, self.pendingAction == nil {
                        if Date().timeIntervalSince(self.lastRetreatAt) < 600 {
                            self.logActivity("🏃 الهروب انطلق قبل شوية — مش هكرره (الهجوم لسه في السكة طبعًا)")
                        } else {
                            self.lastRetreatAt = Date()
                            self.logActivity("🏃 بجهز الهروب لوجهة الهروب المسجلة...")
                            self.startRetreat(auto: true)
                        }
                    }
                } else if hasMov {
                    let df = DateFormatter()
                    df.dateFormat = "HH:mm"
                    self.alertStatus = "آمن ✅ — آخر فحص \(df.string(from: Date())) (حركات: \(moves)، مفيش هجوم)"
                } else {
                    self.alertStatus = "⚠️ الصفحة الحالية مفيهاش صندوق تحركات القرية — افتح قريتك عشان الفحص يشتغل"
                }
            }
        }
    }

    /// 🔔 اختبار التنبيه: إشعار حقيقي عشان تتأكد إن الإشعارات واصلة لموبايلك
    func testAlert() {
        logActivity("🔔 اختبار تنبيه — لو الإشعار ظهر فوق يبقى كل حاجة تمام")
        sendNotification(title: "🔔 تنبيه تجريبي", body: "لو شايف الإشعار ده يبقى تنبيه الهجوم هيوصلك وقت الخطر")
    }

    /// تجسس بالإحداثيات المكتوبة يدوياً في الكارت.
    func spyFromManualCoords() {
        let x = Int(manualSpyX) ?? 0
        let y = Int(manualSpyY) ?? 0
        startSpy(x: x, y: y, name: "الهدف (\(x)|\(y))")
    }

    /// هجوم بالإحداثيات المكتوبة يدوياً.
    func attackFromManualCoords() {
        let x = Int(manualSpyX) ?? 0
        let y = Int(manualSpyY) ?? 0
        startAttack(x: x, y: y, name: "الهدف (\(x)|\(y))")
    }

    /// يحوّل رابط نسبي (/dorf1.php) لرابط كامل على سيرفر اللعبة.
    private func absoluteGameHref(_ href: String) -> String {
        if href.hasPrefix("http") { return href }
        if href.hasPrefix("/") { return "https://utatar.com" + href }
        if href.isEmpty { return gameURL }
        return "https://utatar.com/" + href
    }

    /// يفتح صفحة الخريطة — بدل ما نفترض الرابط، ندور على لينك الخريطة الحقيقي في الصفحة.
    func openMap() {
        let js = """
        (function(){
          var a=document.querySelector('a[href*="karte"], a[href*="map"], [title*="خريطة"]');
          if(a && a.getAttribute('href')) return a.getAttribute('href');
          return '';
        })();
        """
        webView?.evaluateJavaScript(js) { [weak self] res, _ in
            var target = "https://utatar.com/karte.php"
            if let href = res as? String, !href.isEmpty {
                if href.hasPrefix("http") {
                    target = href
                } else if href.hasPrefix("/") {
                    target = "https://utatar.com" + href
                } else {
                    target = "https://utatar.com/" + href
                }
            }
            if let url = URL(string: target) {
                self?.webView?.load(URLRequest(url: url))
            }
        }
    }

    /// تقرير تشخيص الـ DOM الحقيقي — نعرضه في التطبيق والمستخدم يشاركنه.
    func runDiagnostics() {
        diagnosticsOutput = "جاري الفحص..."
        engine.runDiagnostics { [weak self] text in
            DispatchQueue.main.async {
                self?.diagnosticsOutput = text
            }
        }
    }
    
    // MARK: - JavaScript Injection
    
    func collectGameState() {
        let js = """
        (function() {
            try {
                // Try to get resource values from the game
                var resources = {};
                
                // Common Travian-like game selectors
                var woodEl = document.querySelector('#l1, .l1, [class*="wood"], [id*="wood"], .resource_wood');
                var clayEl = document.querySelector('#l2, .l2, [class*="clay"], [id*="clay"], .resource_clay');
                var ironEl = document.querySelector('#l3, .l3, [class*="iron"], [id*="iron"], .resource_iron');
                var wheatEl = document.querySelector('#l4, .l4, [class*="wheat"], [id*="wheat"], .resource_wheat');
                
                if (woodEl) resources.wood = woodEl.textContent.trim();
                if (clayEl) resources.clay = clayEl.textContent.trim();
                if (ironEl) resources.iron = ironEl.textContent.trim();
                if (wheatEl) resources.wheat = wheatEl.textContent.trim();
                
                // Check for attack warnings
                var attackWarning = document.querySelector('.attack_warning, .incoming_attack, [class*="attack"]');
                resources.hasAttack = attackWarning !== null;
                
                // Check for building complete
                var buildComplete = document.querySelector('.build_complete, [class*="complete"]');
                resources.hasBuildComplete = buildComplete !== null;
                
                return JSON.stringify(resources);
            } catch(e) {
                return JSON.stringify({error: e.message});
            }
        })();
        """
        
        webView?.evaluateJavaScript(js) { [weak self] result, error in
            if let jsonString = result as? String,
               let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                DispatchQueue.main.async {
                    self?.woodAmount = json["wood"] as? String ?? "0"
                    self?.clayAmount = json["clay"] as? String ?? "0"
                    self?.ironAmount = json["iron"] as? String ?? "0"
                    self?.wheatAmount = json["wheat"] as? String ?? "0"
                    
                    if json["hasAttack"] as? Bool == true {
                        self?.sendNotification(title: "⚠️ هجوم قادم!", body: "في هجوم جاي على قريتك!")
                    }
                }
            }
        }
    }
    
    func injectAutoCollect() {
        let js = """
        (function() {
            try {
                // Auto collect resources if there's a collect button
                var collectBtn = document.querySelector('.collect_btn, [class*="collect"], .reward_collect');
                if (collectBtn) {
                    collectBtn.click();
                    return 'collected';
                }
                
                // Auto accept resource bonus/rewards
                var rewardBtn = document.querySelector('.reward_accept, [class*="reward"], .bonus_collect');
                if (rewardBtn) {
                    rewardBtn.click();
                    return 'reward_collected';
                }
                
                return 'nothing_to_collect';
            } catch(e) {
                return 'error: ' + e.message;
            }
        })();
        """
        
        webView?.evaluateJavaScript(js) { result, error in
            if let result = result as? String, result.contains("collected") {
                print("✅ Auto-collected resources")
            }
        }
    }
    
    func injectAutoBuild() {
        let js = """
        (function() {
            try {
                // Check if there's a building queue with empty slots
                var buildQueue = document.querySelector('.build_queue, [class*="queue"], #building_queue');
                var upgradeBtns = document.querySelectorAll('.upgrade_btn, [class*="upgrade"], .build_btn, [class*="level_up"]');
                
                // Only auto-build if queue is not full
                var queueItems = document.querySelectorAll('.queue_item, [class*="queue_item"]');
                if (queueItems.length < 2 && upgradeBtns.length > 0) {
                    // Click the first available upgrade button
                    upgradeBtns[0].click();
                    return 'building_started';
                }
                
                return 'queue_full_or_nothing';
            } catch(e) {
                return 'error: ' + e.message;
            }
        })();
        """
        
        webView?.evaluateJavaScript(js) { result, error in
            if let result = result as? String, result.contains("building_started") {
                self.sendNotification(title: "🏗️ بناء تلقائي", body: "بدأنا بناء مبنى جديد!")
            }
        }
    }
    
    /// التدريب المستمر المجدول: كل نوع بالعدد الكتابي اللي كتبته — كل trainIntervalMin دقيقة.
    /// force=true يعني البوت واصل الصفحة بنفسه الحالية → يدرب حالا من غير انتظار الفترة.
    private var intervalNoteShown = false

    func injectAutoTrain(force: Bool = false) {
        guard pendingAction == nil, Date() >= trainCooldownUntil else { return }
        // الفترة بتتحترم دايمًا — حتى لما البوت يوصل الصفحة بنفسه
        guard Date() >= nextQueuedTrainAt else {
            if !intervalNoteShown {
                intervalNoteShown = true
                let mins = max(1, Int(((nextQueuedTrainAt.timeIntervalSinceNow) / 60.0).rounded(.up)))
                logActivity("🐴 التدريب الجاي بعد \(mins) دقيقة")
            }
            return
        }
        let catalog = trainingCatalog
        guard !catalog.isEmpty else {
            if !barracksHintShown {
                barracksHintShown = true
                logActivity("🐴 التدريب المستمر: افتح الثكنة/الإسطبل مرة واحدة عشان ألقط الأنواع وأحفظها عندى")
            }
            return
        }
        // الأنواع المحددة: العدد المكتوب (أي رقم — حتى مليون). الفاضي = مش هيتدرب.
        var typed: [(uid: Int, amount: Int, inputName: String)] = []
        for u in catalog {
            let raw = (trainCounts[u.id] ?? "").filter { $0.isNumber }
            if let n = Int(raw), n > 0 {
                let uid = u.unitId != 0 ? u.unitId : Self.uidFromKey(u.id)
                if uid > 0 { typed.append((uid, n, u.id)) }
            }
        }
        guard !typed.isEmpty else {
            if !barracksHintShown {
                barracksHintShown = true
                logActivity("🐴 اكتب العدد جنب كل نوع عايز تدربه (أي رقم كتابي — 100 أو 1000000)")
            }
            return
        }
        // واقفين في الثكنة؟ استخدم فورم الصفحة (نفس لوجك زرار "درّب" بالظبط).
        // أي صفحة تانية؟ طلب مباشر مخفي للخادم — من غير أي تنقل أو رفرش خالص.
        if pageKind == "build" {
            fireTraining(typed.map { ($0.inputName, $0.amount) }, fetchPairs: typed.map { ($0.uid, $0.amount) })
        } else if !barracksPath.isEmpty {
            fireTraining([], fetchPairs: typed.map { ($0.uid, $0.amount) })
        } else {
            if !barracksHintShown {
                barracksHintShown = true
                logActivity("🐴 افتح الثكنة مرة واحدة بس عشان أتعلم عنوانها — بعدها هدرب من أي صفحة ومن غير ما أفتحها")
            }
        }
    }

    private static func uidFromKey(_ key: String) -> Int {
        let digits = key.filter { $0.isNumber }
        return Int(digits) ?? 0
    }

    /// تنفيذ التدريب الفعلي + ضبط الفترة الجاية + التحقق من قبول اللعبة.
    /// pairs = فورم الصفحة الحالية (لما نكون في الثكنة). fetchPairs = التدريب المخفي من أي صفحة.
    private func fireTraining(_ pairs: [(String, Int)], fetchPairs: [(Int, Int)]? = nil) {
        let onBarracks = !pairs.isEmpty
        let handler: (Bool, String) -> Void = { [weak self] ok, msg in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if msg == "__pending__" {
                    // الطلب لسه في الطريق — الدورة الجاية (30 ثانية) هتتكفل
                    return
                }
                if ok {
                    self.barracksHintShown = false
                    self.intervalNoteShown = false
                    self.ensureTrainQueued(withinMinutes: self.trainIntervalMin)
                    self.markSubmitBusy()
                    self.logActivity("🐴 تدريب مجدول: \(msg) — طلبت تاني بعد \(self.trainIntervalMin) دقيقة ✅")
                } else if msg.contains("مش كفاية") {
                    // الموارد خلصت: إعادة جدولة بصمت — من غير تنقل ولا رفرش
                    self.ensureTrainQueued(withinMinutes: max(1, min(self.trainIntervalMin, 5)))
                    if Date().timeIntervalSince(self.lastShortageLogAt) > 120 {
                        self.lastShortageLogAt = Date()
                        let mins = max(1, min(self.trainIntervalMin, 5))
                        self.logActivity("🌵 \(msg) — في محاولة تانية بعد \(mins) دقيقة ✅")
                    }
                } else if onBarracks {
                    self.gotoBarracks(failReason: msg)
                } else {
                    // في وضع fetch ممنوع نتنقل — نسجل ونحاول في الدورة الجاية
                    self.logActivity("⚠️ \(msg) — هجرب تاني في الدورة الجاية")
                }
            }
        }

        if onBarracks {
            // نفس لوجك زرار "درّب": فورم الصفحة + التحقق بعد ثواني
            engine.trainSelected(pairs) { ok, msg in
                handler(ok, msg)
                if ok {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                        guard let self = self else { return }
                        self.engine.trainCheck { state in
                            DispatchQueue.main.async {
                                if state.hasPrefix("still") {
                                    let reply = String(state.dropFirst(5))
                                    self.logActivity("⚠️ اللعبة ما قبلتش — ردها:\(reply.isEmpty ? " (مفيش رسالة)" : reply)")
                                }
                            }
                        }
                    }
                }
            }
        } else if let fetchPairs = fetchPairs {
            // الأفضل: إعادة ضغطة المستخدم المسجلة (نفس الحقول اللي نجحت بالظبط)
            let saved = lastTrainPost
            if saved["body", default: ""].isEmpty {
                engine.trainViaFetch(barracksPath: barracksPath, pairs: fetchPairs, completion: handler)
            } else {
                engine.trainReplay(saved: saved, pairs: fetchPairs, completion: handler)
            }
        }
    }

    /// كتالوج التدريب: الحي لو موجود، وإلا الملقوطة المحفوظة
    var trainingCatalog: [TrainableUnit] {
        if !trainableUnits.isEmpty { return trainableUnits }
        return Self.decodeUnits(savedTroopTypes)
    }

    var savedUnitIds: Set<String> {
        Set(savedTroopTypes.compactMap { $0["id"] as? String })
    }

    private func captureTroopTypes(_ units: [TrainableUnit]) {
        guard !units.isEmpty else { return }
        // دمج مش استبدال: الثكنة + الإسطبل + الورشة كلهم يتراكموا مع بعض
        var byId: [String: TrainableUnit] = [:]
        for u in Self.decodeUnits(savedTroopTypes) { byId[u.id] = u }
        for u in units { byId[u.id] = u }
        let merged = byId.values.sorted { $0.unitId < $1.unitId }
        let oldIds = Set(savedTroopTypes.compactMap { $0["id"] as? String })
        let newIds = Set(merged.map { $0.id })
        guard newIds != oldIds else { return }
        savedTroopTypes = Self.encodeUnits(merged)
        logActivity("🎒 حفظت \(merged.count) نوع جنود (ثكنة+إسطبل مجتمعين) — تقدر تحدد اللي تحبه وتكتب العدد")
    }

    private static func encodeUnits(_ units: [TrainableUnit]) -> [[String: Any]] {
        units.map { ["id": $0.id, "name": $0.name, "uid": $0.unitId, "max": $0.max, "costW": $0.costWood, "costC": $0.costClay, "costI": $0.costIron, "costCr": $0.costCrop] as [String: Any] }
    }

    private static func decodeUnits(_ arr: [[String: Any]]) -> [TrainableUnit] {
        arr.compactMap { d in
            guard let id = d["id"] as? String else { return nil }
            var u = TrainableUnit(id: id, name: d["name"] as? String ?? "")
            u.unitId = d["uid"] as? Int ?? 0
            u.max = d["max"] as? Int ?? 0
            u.costWood = d["costW"] as? Int ?? 0
            u.costClay = d["costC"] as? Int ?? 0
            u.costIron = d["costI"] as? Int ?? 0
            u.costCrop = d["costCr"] as? Int ?? 0
            return u
        }
    }

    /// 🔬 تجربة تشخيص: تدريب واحد من كل نوع فورًا (من غير مهلة) — عشان نعرف في ثانية هل الخادم بيقبل ولا لأ وبينطي إيه.
    func testTrainOnce() {
        guard pendingAction == nil else {
            logActivity("🔬 فيه مهمة شغالة — نجرب بعد ما تخلص")
            return
        }
        logActivity("🔬 تجربة تدريب واحدة من كل نوع...")
        engine.trainBlind(count: 1) { [weak self] ok, msg in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if ok {
                    if let url = self.webView?.url { self.barracksPath = Self.trainablePath(from: url) }
                    self.markSubmitBusy()
                    self.logActivity("🔬 \(msg) — افتح الثكنة بعد 5 ثواني وشوف طابور التدريب")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                        guard let self = self else { return }
                        self.engine.trainCheck { state in
                            DispatchQueue.main.async {
                                if state.hasPrefix("still") {
                                    let reply = String(state.dropFirst(5))
                                    self.logActivity("⚠️ اللعبة ما قبلتش — ردها:\(reply.isEmpty ? " (مفيش رسالة)" : reply)")
                                } else if state == "gone" {
                                    self.logActivity("✅ الصفحة اتنقلت = التدريب اتقبل على الأغلب — اتأكد من طابور الثكنة")
                                }
                            }
                        }
                    }
                } else {
                    self.gotoBarracks(failReason: msg)
                }
            }
        }
    }

    /// من URL كامل: المسار مع علامة الاستفهام (من غير vid2 عشان يشتغل مع أي قريتنا الحالية)
    private static func trainablePath(from url: URL) -> String {
        var path = url.path
        if let q = url.query {
            let parts = q.components(separatedBy: "&").filter { !$0.hasPrefix("vid2") }
            if !parts.isEmpty { path += "?" + parts.joined(separator: "&") }
        }
        return path
    }

    /// رايح للثكنة: الأول بنجرب الكاش، وبعدين ندور على لينك "ثكنة" في الصفحة، ولو مش لاقيين نمشي لـ dorf2.
    private func gotoBarracks(failReason: String) {
        guard pendingAction == nil, Date() >= submitQuietUntil else { return }
        let cur = webView?.url.map { Self.trainablePath(from: $0) } ?? ""

        if !barracksPath.isEmpty {
            if cur == barracksPath {
                // واقفين في الثكنة أصلاً — الفورمة مش متاحة دلوقتي، ما نمشيش في حتة تانية
                if !barracksHintShown {
                    barracksHintShown = true
                    logActivity("🐴 \(failReason) — واقف في الثكنة بس الفورمة مش متاحة دلوقتي")
                }
                return
            }
            if !barracksHintShown {
                barracksHintShown = true
                logActivity("🐴 \(failReason) — رايح الثكنة (\(barracksPath))")
            }
            navigate(path: barracksPath)
            return
        }

        engine.findBarracksLink { [weak self] href in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let href = href, !href.isEmpty, let u = URL(string: href) {
                    self.barracksPath = Self.trainablePath(from: u)
                    self.logActivity("🐴 \(failReason) — لقيت الثكنة، رايحلها (\(self.barracksPath))")
                    self.navigate(path: self.barracksPath)
                } else if !self.barracksHintShown {
                    self.barracksHintShown = true
                    self.logActivity("🐴 \(failReason) — افتح الثكنة مرة واحدة في اللعبة عشان التطبيق يتعلم مكانها ويمشي لوحده")
                }
            }
        }
    }

    /// آخر تنقل عمله البوت بنفسه — بنستخدمه علشان نعرف إن الصفحة الحالية جاية من البوت
    private var lastBotNavAt = Date.distantPast
    /// آخر تنقل المستخدم عمله بإيده — البوت ماينقلش لو المستخدم لسه بيتحرك (دي كانت سبب "بيرجعني للصفحة الرئيسة")
    private var lastUserNavAt = Date.distantPast
    private var userActiveHintShown = false

    /// نندها من الكووردinator أول ما أي تنقل يقرر — لو مش من البوت يبقى المستخدم هو اللي بيتحرك
    func noteNavigation() {
        if Date().timeIntervalSince(lastBotNavAt) > 3 {
            lastUserNavAt = Date()
            userActiveHintShown = false
        }
    }

    func navigate(path: String, essential: Bool = false) {
        // المستخدم ماسك اللعبة دلوقتي؟ البوت يسيبه (إلا الهروب — ده ضروري)
        if !essential, Date().timeIntervalSince(lastUserNavAt) < 45 {
            if !userActiveHintShown {
                userActiveHintShown = true
                logActivity("✋ لسه بتستخدم اللعبة — مش هنقل وراك لحد ما تسيبها شوية")
            }
            return
        }
        guard Date() >= submitQuietUntil else {
            logActivity("⏳ مستني تأكيد الإرسال — مش بنقل دلويتي")
            return
        }
        let clean = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: "https://utatar.com/" + clean) else { return }
        lastBotNavAt = Date()
        webView?.load(URLRequest(url: url))
    }

    func checkForAttacks() {
        let js = """
        (function() {
            try {
                var attacks = document.querySelectorAll('.incoming_attack, [class*="attack_warning"], .attack_row');
                return attacks.length > 0 ? 'attacks_found:' + attacks.length : 'no_attacks';
            } catch(e) {
                return 'error';
            }
        })();
        """
        
        webView?.evaluateJavaScript(js) { [weak self] result, _ in
            if let result = result as? String, result.contains("attacks_found") {
                let count = result.components(separatedBy: ":").last ?? "?"
                self?.sendNotification(title: "⚠️ هجمات قادمة!", body: "في \(count) هجوم جايين على قريتك!")
            }
        }
    }
    
    func checkResourcesFull() {
        let js = """
        (function() {
            try {
                // Check if warehouse is full
                var warehouseFull = document.querySelector('.warehouse_full, [class*="full"], .storage_full');
                var granaryFull = document.querySelector('.granary_full, [class*="granary_full"]');
                
                var warnings = [];
                if (warehouseFull) warnings.push('warehouse');
                if (granaryFull) warnings.push('granary');
                
                return warnings.length > 0 ? 'full:' + warnings.join(',') : 'ok';
            } catch(e) {
                return 'error';
            }
        })();
        """
        
        webView?.evaluateJavaScript(js) { [weak self] result, _ in
            if let result = result as? String, result.contains("full:") {
                self?.sendNotification(title: "📦 مخزن مليان!", body: "المخزن بتاعك مليان - الموارد بتتوقف!")
            }
        }
    }
    
    // MARK: - Custom JavaScript
    
    func executeCustomJS(_ script: String) {
        webView?.evaluateJavaScript(script) { result, error in
            if let error = error {
                print("JS Error: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Notifications
    
    func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        
        DispatchQueue.main.async {
            self.alertMessage = "\(title)\n\(body)"
            self.showAlert = true
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}
