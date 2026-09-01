import Foundation
import WebKit

// MARK: - GameEngine
//
// محرك قراءة حقيقي للعبة "عصر التتار" (محرك Travian الكلاسيكي).
// بدل التخمين، بنستخدم الـ DOM الحقيقي للعبة:
//   - شريط الموارد:  #l1 خشب / #l2 طين / #l3 حديد / #l4 قمح (صيغة "الحالي/السعة")
//   - نقطة التجمع:   build.php?id=39  (جنود القرية + إرسال الهجمات a2b.php)
//   - الثكنات:       build.php?id=19 (تدريب، input اسمه t1..t10 + رابط الحد الأقصى)
//   - الخريطة:       karte.php       (قرى حقيقية بإحداثيات وروابط karte.php?d=)
//   - التقارير:      berichte.php    (تقارير التجسس: موارد + جنود + جدار)
// ولو أي selector ما لقاش حاجة، بنرجّع fallback عام بدل ما نفشل بصمت.

// MARK: - Models

struct GameResources: Equatable {
    var wood = 0
    var clay = 0
    var iron = 0
    var crop = 0
    var woodCap = 0
    var clayCap = 0
    var ironCap = 0
    var cropCap = 0
    var cropProd = 0

    var summary: String {
        "🪵\(wood) 🧱\(clay) ⚙️\(iron) 🌾\(crop)"
    }
}

struct HomeUnit: Identifiable, Equatable {
    let id: Int        // رقم الوحدة 1..30 (u1..u30 في اللعبة)
    var name: String
    var count: Int
}

struct TrainableUnit: Identifiable, Equatable {
    let id: String     // اسم الـ input الحقيقي في الفورم (t1..t10)
    var name: String
    var max = 0        // الحد الأقصى القابل للتدريب دلوقتي (من اللعبة نفسها)
    var costWood = 0
    var costClay = 0
    var costIron = 0
    var costCrop = 0

    /// أدنى تكلفة مورد = أقصى عدد نقدر نكلفه بالمورد الأضيق.
    func affordable(with r: GameResources) -> Int {
        var m = Int.max
        let caps: [(Int, Int)] = [
            (costWood, r.wood), (costClay, r.clay),
            (costIron, r.iron), (costCrop, r.crop),
        ]
        for (cost, have) in caps where cost > 0 {
            m = min(m, have / cost)
        }
        if m == Int.max { return max }
        return min(m, max)
    }
}

struct MapVillage: Identifiable, Equatable {
    let id: String     // رقم القرية من الرابط d=12345
    var name: String
    var x = 0
    var y = 0
    var player = ""
    var population = 0
    var href = ""      // الرابط الكامل karte.php?d=...&c=... لفتح القرية
}

struct ScoutReport: Identifiable {
    let id: String
    var subject: String
    var dateText: String
    var wood = 0
    var clay = 0
    var iron = 0
    var crop = 0
    var wallLevel = -1
    var troopsText = ""
}

// MARK: - Engine

final class GameEngine: NSObject {
    weak var webView: WKWebView?

    func attach(_ webView: WKWebView?) {
        self.webView = webView
    }

    // MARK: تشخيص الصفحة

    /// نوع الصفحة الحالية من الرابط نفسه (مضمون 100% بدل التخمين في الـ DOM).
    static func pageKind(from urlString: String) -> String {
        guard let url = URL(string: urlString),
              let host = url.host, host.contains("utatar") else { return "other" }
        let path = url.lastPathComponent.lowercased()
        let q = url.query ?? ""
        if path.hasPrefix("dorf1") { return "dorf1" }
        if path.hasPrefix("dorf2") { return "dorf2" }
        if path.hasPrefix("a2b") { return "a2b" }
        if path.hasPrefix("karte") { return q.contains("d=") ? "villageInfo" : "map" }
        if path.hasPrefix("map") { return "map" }
        if q.contains("d=") { return "villageInfo" }
        if path.hasPrefix("build") {
            if q.range(of: #"id=(19|20|21|25|26|29|30)"#, options: .regularExpression) != nil {
                return "training"
            }
            return "building"
        }
        if path.hasPrefix("berichte") { return "reports" }
        if path.hasPrefix("login") || path.hasPrefix("sign") || path.hasPrefix("anmelden") {
            return "login"
        }
        return "other"
    }

    /// تنفيذ JS وترجع JSON String مفكوك كمفتاح/قيمة.
    private func runJSON(_ js: String, completion: @escaping ([String: Any]?) -> Void) {
        guard let webView = webView else {
            completion(nil)
            return
        }
        webView.evaluateJavaScript(js) { result, _ in
            guard let s = result as? String,
                  let data = s.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil)
                return
            }
            completion(obj)
        }
    }

    /// تنفيذ JS وترجعة JSON String مفكوكة كمصفوفة.
    private func runJSONArray(_ js: String, completion: @escaping ([[String: Any]]?) -> Void) {
        guard let webView = webView else {
            completion(nil)
            return
        }
        webView.evaluateJavaScript(js) { result, _ in
            guard let s = result as? String,
                  let data = s.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                completion(nil)
                return
            }
            completion(obj)
        }
    }

    // MARK: - الموارد (حقيقية من #l1..#l4)

    func readResources(completion: @escaping (GameResources?) -> Void) {
        runJSON(Self.resourcesJS) { obj in
            guard let obj = obj, let res = obj["resources"] as? [String: Any] else {
                completion(nil)
                return
            }
            var g = GameResources()
            g.wood = Self.int(res["wood"])
            g.clay = Self.int(res["clay"])
            g.iron = Self.int(res["iron"])
            g.crop = Self.int(res["crop"])
            g.woodCap = Self.int(res["woodCap"])
            g.clayCap = Self.int(res["clayCap"])
            g.ironCap = Self.int(res["ironCap"])
            g.cropCap = Self.int(res["cropCap"])
            g.cropProd = Self.int(res["cropProd"])
            completion(g)
        }
    }

    /// جافاسكريبت قراءة الموارد: كلاسيكيتع #l1..#l4 + مسح عام لأي صف أرقام في أعلى الصفحة.
    static let resourcesJS = """
    (function(){
      function pi(x){ var n=parseInt(String(x).replace(/[^0-9]/g,''),10); return isNaN(n)?0:n; }
      var vals=[0,0,0,0], caps=[0,0,0,0], got=0;
      // 1) المحاولة الكلاسيكية: #l1..#l4 (صيغة الحالي/السعة في الـ title أو النص)
      for(var i=0;i<4;i++){
        var el=document.querySelector('#l'+(i+1)+', .l'+(i+1));
        if(!el) continue;
        var t=(el.getAttribute('title')||'')+' '+(el.textContent||'');
        var m=t.match(/([0-9][0-9,.\\s]*)\\s*\\/\\s*([0-9][0-9,.\\s]*)/);
        if(m){ vals[i]=pi(m[1]); caps[i]=pi(m[2]); }
        else vals[i]=pi(el.textContent);
        if(vals[i]>0) got++;
      }
      // 2) مسح عام: أول صف قرب أعلى الصفحة فيه 4 أرقام أو أكثر = شريط الموارد
      if(got<4){
        var groups={};
        document.querySelectorAll('div,span,td,li,a,b,p').forEach(function(e){
          var txt=(e.textContent||'').trim();
          if(!txt || e.children.length>0) return;
          if(!/^[0-9][0-9,.\\s]{2,}$/.test(txt)) return;
          var n=pi(txt); if(n<=0) return;
          var r=e.getBoundingClientRect();
          if(r.width<=0 || r.top<0 || r.top>340) return;
          var key=Math.round(r.top/14);
          (groups[key]=groups[key]||[]).push(n);
        });
        var best=null;
        for(var k in groups){
          var g=groups[k];
          if(g.length>=4 && (!best || g.length>best.length)) best=g;
        }
        if(best){
          var uniq=[], seen={};
          for(var j=0;j<best.length && uniq.length<4;j++){
            if(!seen[best[j]]){ seen[best[j]]=1; uniq.push(best[j]); }
          }
          for(var i2=0;i2<4 && i2<uniq.length;i2++){ if(!(vals[i2]>0)) vals[i2]=uniq[i2]; }
        }
      }
      var prod=0;
      var l5=document.querySelector('#l5');
      if(l5) prod=pi(l5.textContent);
      return JSON.stringify({resources:{
        wood:vals[0], clay:vals[1], iron:vals[2], crop:vals[3],
        woodCap:caps[0], clayCap:caps[1], ironCap:caps[2], cropCap:caps[3],
        cropProd:prod
      }});
    })();
    """

    // MARK: - الجنود الموجودين في القرية

    func readHomeTroops(completion: @escaping ([HomeUnit]) -> Void) {
        runJSONArray(Self.homeTroopsJS) { arr in
            var byId: [Int: HomeUnit] = [:]
            for item in arr ?? [] {
                let id = Self.int(item["id"])
                guard id >= 1, id <= 30 else { continue }
                let name = item["name"] as? String ?? ""
                let count = Self.int(item["count"])
                if var existing = byId[id] {
                    existing.count = max(existing.count, count)
                    if existing.name.isEmpty { existing.name = name }
                    byId[id] = existing
                } else {
                    byId[id] = HomeUnit(id: id, name: name, count: count)
                }
            }
            completion(Array(byId.values).sorted { $0.id < $1.id })
        }
    }

    static let homeTroopsJS = """
    (function(){
      function pi(x){ var n=parseInt(String(x).replace(/[^0-9]/g,''),10); return isNaN(n)?0:n; }
      var out=[];
      var imgs=document.querySelectorAll('img[class*="unit"], img[src*="/u/u"], img[src*="un/u/"], img[src*="img/u/"]');
      imgs.forEach(function(img){
        var m=(img.getAttribute('class')||'')+' '+(img.getAttribute('src')||'');
        var um=m.match(/u(\\d{1,2})/);
        if(!um) return;
        var uid=parseInt(um[1],10);
        if(uid<1||uid>30) return;
        var name=img.getAttribute('title')||img.getAttribute('alt')||'';
        var count=0;
        var tr=img.closest('tr');
        if(tr){
          var v=tr.querySelector('td.val, td[class*="count"], td.un');
          if(v) count=pi(v.textContent);
          if(!count){
            var nums=(tr.textContent||'').match(/\\d+/g)||[];
            if(nums.length) count=pi(nums[nums.length-1]);
          }
        }
        var td=img.closest('td,div');
        if(!count && td && td.parentElement){
          var sib=td.parentElement.textContent||'';
          var sn=sib.match(/\\d+/g);
          if(sn) count=pi(sn[sn.length-1]);
        }
        out.push({id:uid,name:name,count:count});
      });
      return JSON.stringify(out);
    })();
    """

    // MARK: - الوحدات القابلة للتدريب (صفحة الثكنات/الإسطبل/الورشة)

    func readTrainableUnits(completion: @escaping ([TrainableUnit]) -> Void) {
        runJSON(Self.trainableJS) { obj in
            guard let obj = obj else {
                completion([])
                return
            }
            var unitsOut: [TrainableUnit] = []
            for item in obj["units"] as? [[String: Any]] ?? [] {
                let input = item["input"] as? String ?? ""
                guard !input.isEmpty else { continue }
                var u = TrainableUnit(id: input, name: item["name"] as? String ?? "")
                let uid = Self.int(item["uid"])
                if u.name.isEmpty && uid > 0 {
                    u.name = GameEngine.arabicUnitName(uid)
                }
                u.max = Self.int(item["max"])
                let costs = item["costs"] as? [Any] ?? []
                if costs.count >= 4 {
                    u.costWood = Self.int(costs[0])
                    u.costClay = Self.int(costs[1])
                    u.costIron = Self.int(costs[2])
                    u.costCrop = Self.int(costs[3])
                }
                unitsOut.append(u)
            }
            completion(unitsOut)
        }
    }

    static let trainableJS = """
    (function(){
      function pi(x){ var n=parseInt(String(x).replace(/[^0-9]/g,''),10); return isNaN(n)?0:n; }
      function unitIdFromName(n){
        var m=String(n).match(/^t(?:f)?\\[(\\d{1,2})\\]$/i);
        if(m) return parseInt(m[1],10);
        var m2=String(n).match(/^t(\\d{1,2})$/i);
        if(m2) return parseInt(m2[1],10);
        return 0;
      }
      var units=[];
      document.querySelectorAll('form').forEach(function(f){
        // استبعد فورمات إرسال الهجمات (فيها إحداثيات x/y) عشان ما نغلطش نبعث جيش
        if(f.querySelector('input[name="x"]') && f.querySelector('input[name="y"]')) return;
        f.querySelectorAll('input[name]').forEach(function(inp){
          var n=inp.getAttribute('name');
          var uid=unitIdFromName(n);
          if(uid<=0) return;
          for(var i=0;i<units.length;i++){ if(units[i].input===n) return; }
          var row=inp.closest('tr')||inp.closest('div')||inp.parentElement;
          var name='';
          if(row){
            var img=row.querySelector('img[class*="unit"], img[src*="/u/"], img[src*="un/u/"], img[src*="img/u/"]');
            if(img){
              name=img.getAttribute('title')||img.getAttribute('alt')||'';
            }
            if(!name){
              var a=row.querySelector('a');
              if(a) name=(a.getAttribute('title')||a.textContent||'').trim();
            }
          }
          var max=0;
          var mm=parseInt(inp.getAttribute('max'),10);
          if(isNaN(mm)) mm=parseInt(inp.getAttribute('data-max'),10);
          if(!isNaN(mm)&&mm>0) max=mm;
          if(!max){
            var mx=document.querySelector('a[href*="'+n+'.value="]');
            if(mx){ var v=pi(mx.textContent); if(v>0) max=v; }
          }
          if(!max&&row){
            var mxt=row.textContent.match(/\\((\\d+)\\)/);
            if(mxt) max=parseInt(mxt[1],10);
          }
          var cw=0,cc=0,ci=0,cp=0;
          if(row){
            var cells=row.querySelectorAll('img[src*="r1"], img[src*="r2"], img[src*="r3"], img[src*="r4"], img[class*="r1"], img[class*="r2"], img[class*="r3"], img[class*="r4"]');
            var vals=[0,0,0,0];
            cells.forEach(function(c,ix){
              if(ix>3) return;
              var h=c.parentElement;
              var t=h?(h.textContent||''):'';
              var nm=t.match(/\\d+/);
              if(nm) vals[ix]=parseInt(nm[0],10);
            });
            cw=vals[0]; cc=vals[1]; ci=vals[2]; cp=vals[3];
          }
          units.push({input:n, uid:uid, name:name, max:max, costs:[cw,cc,ci,cp]});
        });
      });
      return JSON.stringify({units:units});
    })();
    """

    // MARK: - التدريب (فورم حقيقي بالاسم، مش بالدور!)

    func trainUnit(_ inputName: String, count: Int, completion: ((String) -> Void)? = nil) {
        let js = Self.trainOneJS(inputName: inputName, count: count)
        runJSON(js) { obj in
            let ok = (obj?["ok"] as? Bool) ?? false
            let msg = (obj?["message"] as? String) ?? (ok ? "تم" : "فشل")
            completion?(msg)
        }
    }

    /// يدرّب كل نوع بالعدد الأقصى المسموح (يستخدم قيم max الحقيقية من الصفحة).
    func trainAllMax(_ units: [TrainableUnit], completion: ((String) -> Void)? = nil) {
        let js = Self.trainManyJS(units.map { ($0.id, $0.max > 0 ? $0.max : 0) })
        runJSON(js) { obj in
            let n = (obj?["filled"] as? Int) ?? 0
            completion?(n > 0 ? "تم تعبئة \(n) نوع وبدء التدريب ✅" : "مفيش حاجة اتبعت — تأكد إنك على صفحة الثكنات")
        }
    }

    static func trainOneJS(inputName: String, count: Int) -> String {
        trainManyJS([(inputName, count)])
    }

    static func trainManyJS(_ pairs: [(String, Int)]) -> String {
        var arr = "["
        for (i, p) in pairs.enumerated() {
            let name = p.0.replacingOccurrences(of: "'", with: "")
            arr += "['\(name)',\(p.1)]"
            if i < pairs.count - 1 { arr += "," }
        }
        arr += "]"
        return """
        (function(){
          try{
            var sels=\(arr);
            // دور على الفورم اللي فيه حقول التدريب نفسها (مهما كان الـ action)
            var form=null;
            var allForms=document.querySelectorAll('form');
            for(var fi=0; fi<allForms.length && !form; fi++){
              for(var j=0;j<sels.length;j++){
                if(allForms[fi].querySelector('input[name="'+sels[j][0]+'"]')){ form=allForms[fi]; break; }
              }
            }
            var scope=form||document;
            var probe=scope.querySelector('input[name="'+sels[0][0]+'"]');
            if(!probe) return JSON.stringify({ok:false,filled:0,message:'مفيش حقول تدريب في الصفحة دي — افتح الثكنات الأول'});
            var filled=0;
            function pi(x){ var n=parseInt(String(x).replace(/[^0-9]/g,''),10); return isNaN(n)?0:n; }
            sels.forEach(function(s){
              var inp=scope.querySelector('input[name="'+s[0]+'"]');
              if(!inp) return;
              var v=s[1];
              if(!(v>0)){
                var mx=document.querySelector('a[href*="'+s[0]+'.value="]');
                var mv=mx?pi(mx.textContent):0;
                v=(mv>0)?mv:1;
              }
              var n=String(v);
              var proto=HTMLInputElement.prototype;
              var setter=Object.getOwnPropertyDescriptor(proto,'value').set;
              try{ setter.call(inp,n); }catch(e){ inp.value=n; }
              inp.dispatchEvent(new Event('input',{bubbles:true}));
              inp.dispatchEvent(new Event('change',{bubbles:true}));
              filled++;
            });
            if(filled===0) return JSON.stringify({ok:false,filled:0,message:'لم أجد حقول التدريب'});
            var btn=scope.querySelector('button[type="submit"], input[type="submit"], button[name="s"], input[type="image"], button:not([type])');
            if(btn){ btn.click(); }
            else if(scope.requestSubmit){ scope.requestSubmit(); }
            else { return JSON.stringify({ok:false,filled:filled,message:'وجدت الحقول لكن لا يوجد زر تدريب'}); }
            return JSON.stringify({ok:true,filled:filled,message:'بدأ التدريب ('+filled+' حقل)'});
          }catch(e){ return JSON.stringify({ok:false,filled:0,message:e.message}); }
        })();
        """
    }

    // MARK: - مسح الخريطة (قرى حقيقية بإحداثيات)

    func scanMapVillages(completion: @escaping ([MapVillage]) -> Void) {
        runJSONArray(Self.mapScanJS) { arr in
            var villages: [MapVillage] = []
            var seen = Set<String>()
            for item in arr ?? [] {
                let vid = String(Self.int(item["vid"]))
                guard vid != "0", !seen.contains(vid) else { continue }
                seen.insert(vid)
                var v = MapVillage(
                    id: vid,
                    name: item["name"] as? String ?? "",
                    x: Self.int(item["x"]),
                    y: Self.int(item["y"])
                )
                v.player = item["player"] as? String ?? ""
                v.population = Self.int(item["population"])
                v.href = item["href"] as? String ?? ""
                villages.append(v)
            }
            completion(villages)
        }
    }

    static let mapScanJS = """
    (function(){
      function pi(x){ var n=parseInt(String(x).replace(/[^0-9]/g,''),10); return isNaN(n)?0:n; }
      var out=[];
      function push(href, title){
        var dm=href.match(/d=(\\d+)/);
        if(!dm) return;
        var xy=title.match(/\\((-?\\d{1,4})\\s*\\|\\s*(-?\\d{1,4})\\)/);
        var player='';
        var pm=title.match(/(?:اللاعب|اللاعب:|player)\\s*:?\\s*([^|()]{2,30})/i);
        if(pm) player=pm[1].trim();
        var pop=0;
        var pom=title.match(/(?:السكان|population)\\s*:?\\s*([0-9]+)/i);
        if(pom) pop=parseInt(pom[1],10);
        var name=title.replace(/\\(-?\\d{1,4}\\s*\\|\\s*-?\\d{1,4}\\)/,'').trim();
        if(name.length>40) name=name.substring(0,40);
        out.push({vid:dm[1], name:name, x:xy?parseInt(xy[1],10):0, y:xy?parseInt(xy[2],10):0, player:player, population:pop, href:href});
      }
      document.querySelectorAll('area[href*="karte"], a[href*="karte"]').forEach(function(a){
        push(a.getAttribute('href')||'', a.getAttribute('title')||(a.textContent||'').trim());
      });
      document.querySelectorAll('#map_content div[onclick*="d="]').forEach(function(d){
        var oc=d.getAttribute('onclick')||'';
        var m=oc.match(/d=\\d+/);
        if(m) push('karte?'+m[0], d.getAttribute('title')||(d.textContent||'').trim());
      });
      return JSON.stringify(out);
    })();
    """

    // MARK: - التجسس: فتح القرية ثم إرسال جواسيس

    /// على صفحة معلومات القرية (karte.php?d=): يدوس "إرسال جنود" (رابط a2b).
    func clickSendTroopsFromVillageInfo(completion: @escaping (Bool) -> Void) {
        runJSON(Self.villageInfoSpyJS) { obj in
            completion(((obj?["clicked"] as? Bool) ?? false))
        }
    }

    static let villageInfoSpyJS = """
    (function(){
      try{
        var links=document.querySelectorAll('a[href*="a2b"][href*="d="]');
        if(links.length===0){
          links=document.querySelectorAll('a[href*="a2b"]');
        }
        if(links.length===0){
          links=document.querySelectorAll('a[href*="send"], a[href*="troop"], a[href*="attack"]');
        }
        if(links.length===0){
          var btns=document.querySelectorAll('button, input[type="submit"], [role="button"]');
          for(var i=0;i<btns.length;i++){
            var tx=(btns[i].textContent||btns[i].value||'');
            if(/إرسال|جنود|send/i.test(tx)){ btns[i].click(); return JSON.stringify({clicked:true,via:'text'}); }
          }
          return JSON.stringify({clicked:false});
        }
        links[0].click();
        return JSON.stringify({clicked:true});
      }catch(e){ return JSON.stringify({clicked:false,error:e.message}); }
    })();
    """

    /// على صفحة a2b.php: يملأ عدد الجواسيس (u4 روماني / u14 توتون / u23 غالي) ويرسل غارة.
    func sendScouts(count: Int, completion: @escaping (Bool, String) -> Void) {
        runJSON(Self.scoutSendJS(count: count)) { obj in
            let ok = (obj?["sent"] as? Bool) ?? false
            let msg = (obj?["message"] as? String) ?? ""
            completion(ok, msg)
        }
    }

    static func scoutSendJS(count: Int) -> String {
        """
        (function(){
          try{
            function pi(x){ var n=parseInt(String(x).replace(/[^0-9]/g,''),10); return isNaN(n)?0:n; }
            function unitIdFromName(n){
              var m=String(n).match(/^t(?:f)?\\[(\\d{1,2})\\]$/i);
              if(m) return parseInt(m[1],10);
              var m2=String(n).match(/^t(\\d{1,2})$/i);
              if(m2) return parseInt(m2[1],10);
              return 0;
            }
            var form=null;
            // الأول: فورم إرسال حقيقية (فيها إحداثيات x/y + مدخلات جنود)
            document.querySelectorAll('form').forEach(function(f){
              if(form) return;
              if(f.querySelector('input[name="x"]') && f.querySelector('input[name="y"]') && f.querySelector('input[name^="t"]')) form=f;
            });
            // بعد كده: أي فورم فيها مدخلات جنود
            if(!form){
              document.querySelectorAll('form').forEach(function(f){
                if(form) return;
                if(f.querySelector('input[name^="t"]')) form=f;
              });
            }
            if(!form) return JSON.stringify({sent:false,message:'افتح صفحة إرسال الجنود (نقطة التجمع) الأول'});
            var scout=null;
            form.querySelectorAll('input[name]').forEach(function(inp){
              var uid=unitIdFromName(inp.getAttribute('name'));
              if((uid===14||uid===4||uid===23) && !scout) scout=inp;
            });
            if(!scout) return JSON.stringify({sent:false,message:'مفيش كشاف/مستكشف في صفحة الإرسال دي'});
            var proto=HTMLInputElement.prototype;
            var setter=Object.getOwnPropertyDescriptor(proto,'value').set;
            var maxv=0;
            var mx=document.querySelector('a[href*="'+scout.getAttribute('name')+'.value="]');
            if(mx) maxv=pi(mx.textContent);
            var n=Math.min(\(count), maxv>0?maxv:\(count));
            try{ setter.call(scout,String(n)); }catch(e){ scout.value=String(n); }
            scout.dispatchEvent(new Event('input',{bubbles:true}));
            scout.dispatchEvent(new Event('change',{bubbles:true}));
            var raid=form.querySelector('input[name="c"][value="4"], input[value="4"]');
            if(raid) raid.click();
            var btn=form.querySelector('button[type="submit"], button[name="s"], input[type="submit"], input[type="image"], button:not([type])');
            if(btn){ btn.click(); }
            else if(form.requestSubmit){ form.requestSubmit(); }
            else { return JSON.stringify({sent:false,message:'لا يوجد زر إرسال'}); }
            return JSON.stringify({sent:true,message:'انطلق \(count) من الجواسيس 🕵️'});
          }catch(e){ return JSON.stringify({sent:false,message:e.message}); }
        })();
        """
    }

    // MARK: - الهجوم بإحداثيات (يستخدم a2b الحقيقي)

    func sendAttack(x: Int, y: Int, troops: [(String, Int)], raid: Bool, completion: @escaping (Bool, String) -> Void) {
        runJSON(Self.attackJS(x: x, y: y, troops: troops, raid: raid)) { obj in
            let ok = (obj?["sent"] as? Bool) ?? false
            let msg = (obj?["message"] as? String) ?? ""
            completion(ok, msg)
        }
    }

    static func attackJS(x: Int, y: Int, troops: [(String, Int)], raid: Bool) -> String {
        var arr = "["
        for (i, t) in troops.enumerated() {
            let name = t.0.replacingOccurrences(of: "'", with: "")
            arr += "['\(name)',\(t.1)]"
            if i < troops.count - 1 { arr += "," }
        }
        arr += "]"
        return """
        (function(){
          try{
            var form=null;
            document.querySelectorAll('form').forEach(function(f){
              if(form) return;
              var hx=f.querySelector('input[name="x"]');
              var hy=f.querySelector('input[name="y"]');
              var ht=f.querySelector('input[name^="t"]');
              if(hx&&hy&&ht) form=f;
            });
            if(!form){
              document.querySelectorAll('form').forEach(function(f){
                if(form) return;
                if(f.querySelector('input[name^="t"]')) form=f;
              });
            }
            if(!form) return JSON.stringify({sent:false,message:'افتح نقطة التجمع (القرية ← نقطة التجمع) الأول'});
            var sels=\(arr);
            var filled=0;
            sels.forEach(function(s){
              var inp=form.querySelector('input[name="'+s[0]+'"]');
              if(!inp) return;
              var proto=HTMLInputElement.prototype;
              var setter=Object.getOwnPropertyDescriptor(proto,'value').set;
              try{ setter.call(inp,String(s[1])); }catch(e){ inp.value=String(s[1]); }
              inp.dispatchEvent(new Event('input',{bubbles:true}));
              inp.dispatchEvent(new Event('change',{bubbles:true}));
              filled++;
            });
            if(filled===0) return JSON.stringify({sent:false,message:'مفيش جنود متاحين'});
            var xi=form.querySelector('input[name="x"]');
            var yi=form.querySelector('input[name="y"]');
            if(xi&&yi){
              var proto=HTMLInputElement.prototype;
              var setter=Object.getOwnPropertyDescriptor(proto,'value').set;
              try{ setter.call(xi,String(\(x))); }catch(e){ xi.value=String(\(x)); }
              try{ setter.call(yi,String(\(y))); }catch(e){ yi.value=String(\(y)); }
              xi.dispatchEvent(new Event('change',{bubbles:true}));
              yi.dispatchEvent(new Event('change',{bubbles:true}));
            }
            var mode=form.querySelector(raid?'input[name="c"][value="4"]':'input[name="c"][value="3"]');
            if(mode) mode.click();
            var btn=form.querySelector('button[name="s"], button[type="submit"], input[type="image"][name="s1"], input[type="submit"], button:not([type])');
            if(btn){ btn.click(); }
            else if(form.requestSubmit){ form.requestSubmit(); }
            else { return JSON.stringify({sent:false,message:'لا يوجد زر إرسال'}); }
            return JSON.stringify({sent:true,message:'الهجوم انطلق ⚔️'});
          }catch(e){ return JSON.stringify({sent:false,message:e.message}); }
        })();
        """
    }

    // MARK: - قراءة تقارير التجسس (الموارد والجنود والجدار)

    func readSpyReports(limit: Int = 8, completion: @escaping ([ScoutReport]) -> Void) {
        runJSON(Self.reportsJS(limit: limit)) { obj in
            var found: [ScoutReport] = []
            for item in obj?["reports"] as? [[String: Any]] ?? [] {
                let id = String(Self.int(item["id"]))
                var rep = ScoutReport(
                    id: id,
                    subject: item["subject"] as? String ?? "",
                    dateText: item["date"] as? String ?? ""
                )
                rep.wood = Self.int(item["wood"])
                rep.clay = Self.int(item["clay"])
                rep.iron = Self.int(item["iron"])
                rep.crop = Self.int(item["crop"])
                rep.wallLevel = Self.int(item["wall"]) - 1
                rep.troopsText = item["troops"] as? String ?? ""
                found.append(rep)
            }
            completion(found)
        }
    }

    static func reportsJS(limit: Int) -> String {
        """
        (function(){
          function pi(x){ var n=parseInt(String(x).replace(/[^0-9]/g,''),10); return isNaN(n)?0:n; }
          var links=[];
          document.querySelectorAll('a[href*="berichte.php?id="]').forEach(function(a){
            if(links.length>=\(max(1, limit))) return;
            var href=a.getAttribute('href')||'';
            var m=href.match(/id=(\\d+)/);
            var row=a.closest('tr,div');
            var subject=(a.getAttribute('title')||(row?row.textContent:a.textContent)||'').replace(/\\s+/g,' ').trim();
            if(m && subject.length>0) links.push({id:m[1], subject:subject.substring(0,60), href:href});
          });
          if(links.length===0) return Promise.resolve(JSON.stringify({reports:[]}));
          return new Promise(function(resolve){
            var reports=[]; var done=0; var finished=false;
            function maybeFinish(){
              if(!finished && done>=links.length){ finished=true; resolve(JSON.stringify({reports:reports})); }
            }
            setTimeout(maybeFinish, 8000);
            links.forEach(function(l){
              fetch(l.href, {credentials:'same-origin'})
                .then(function(r){ return r.text(); })
                .then(function(html){
                  var doc=new DOMParser().parseFromString(html,'text/html');
                  var rep={id:l.id, subject:l.subject, date:'', wood:0, clay:0, iron:0, crop:0, wall:0, troops:''};
                  var resTds=doc.querySelectorAll('#resource td, td[class*="res"]');
                  var vals=[];
                  resTds.forEach(function(td){
                    var n=pi(td.textContent);
                    if(n>0 && vals.length<4) vals.push(n);
                  });
                  if(vals.length>=4){ rep.wood=vals[0]; rep.clay=vals[1]; rep.iron=vals[2]; rep.crop=vals[3]; }
                  var body=doc.body?doc.body.innerText:'';
                  var wm=body.match(/(?:الجدار|السور|wall)[^0-9]{0,15}([0-9]{1,2})/i);
                  if(wm) rep.wall=parseInt(wm[1],10)+1;
                  var dm=body.match(/[0-9]{1,2}\\.[0-9]{1,2}\\.[0-9]{2,4}[^\\n]{0,8}/);
                  if(dm) rep.date=dm[0];
                  var troops=[];
                  doc.querySelectorAll('img[class*="unit"], img[src*="/u/"]').forEach(function(img){
                    var um=((img.getAttribute('class')||'')+' '+(img.getAttribute('src')||'')).match(/u(\\d{1,2})/);
                    if(!um) return;
                    var tr=img.closest('tr');
                    if(!tr) return;
                    var nums=(tr.textContent||'').match(/\\d+/g)||[];
                    if(nums.length) troops.push('u'+um[1]+':'+nums[nums.length-1]);
                  });
                  rep.troops=troops.slice(0,12).join(' ');
                  reports.push(rep);
                  done++; maybeFinish();
                })
                .catch(function(){ done++; maybeFinish(); });
            });
          });
        })();
        """
    }

    // MARK: - تشخيص الصفحة (يطلع تقرير الـ DOM الحقيقي)

    func runDiagnostics(completion: @escaping (String) -> Void) {
        runJSON(Self.diagnosticsJS) { obj in
            let lines = obj?["lines"] as? [Any] ?? []
            let text = lines.compactMap { $0 as? String }.joined(separator: "\n")
            completion(text.isEmpty ? "مفيش نتيجة — اتأكد إن اللعبة مفتوحة" : text)
        }
    }

    static let diagnosticsJS = """
    (function(){
      function brief(el){
        var s='<'+el.tagName.toLowerCase();
        if(el.id) s+='#'+el.id;
        var c=String(el.className||'').trim();
        if(c) s+='.'+c.split(/\\s+/).join('.');
        return s+'>';
      }
      var out=[];
      out.push('URL: '+location.href);
      out.push('TITLE: '+(document.title||''));
      out.push('== FORMS ==');
      document.querySelectorAll('form').forEach(function(f,fi){
        var act=f.getAttribute('action')||'-';
        var mth=(f.getAttribute('method')||'get').toLowerCase();
        out.push('F'+fi+' '+mth+' '+act.substring(0,70));
        f.querySelectorAll('input,button,select,textarea').forEach(function(i,ii){
          if(ii>=16) return;
          var t=i.tagName.toLowerCase();
          var line='  '+t+' name='+(i.getAttribute('name')||'-')+' type='+(i.getAttribute('type')||'-');
          var mx=i.getAttribute('max')||i.getAttribute('data-max');
          if(mx) line+=' max='+mx;
          var ph=i.getAttribute('placeholder');
          if(ph) line+=' ph='+ph.substring(0,15);
          if(t=='button'||i.getAttribute('type')=='submit'){
            var tx=(i.textContent||i.value||'').trim();
            if(tx) line+=' text='+tx.substring(0,20);
          }
          out.push(line);
        });
      });
      out.push('== LINKS ==');
      var seen={};
      document.querySelectorAll('a[href]').forEach(function(a){
        if(out.length>115) return;
        var h=a.getAttribute('href')||'';
        if(!/karte|map|a2b|build|berichte|spy|attack|send|dorf/.test(h)) return;
        if(seen[h]) return; seen[h]=1;
        var tx=(a.textContent||a.getAttribute('title')||'').trim().replace(/\\s+/g,' ').substring(0,24);
        out.push(h.substring(0,90)+' "'+tx+'"');
      });
      out.push('== TOPNUM ==');
      var nums=0;
      document.querySelectorAll('div,span,td,li,a,b,p').forEach(function(e){
        if(nums>=8) return;
        var t=(e.textContent||'').trim();
        if(e.children.length===0 && /^[0-9][0-9,.\\s]{2,}$/.test(t)){
          var r=e.getBoundingClientRect();
          if(r.width>0&&r.top>=0&&r.top<=340){
            out.push(brief(e)+' top='+Math.round(r.top)+' "'+t.substring(0,20)+'"'); nums++;
          }
        }
      });
      out.push('== UNITS ==');
      var u=0;
      document.querySelectorAll('img').forEach(function(im){
        if(u>=12) return;
        var m=((im.getAttribute('class')||'')+' '+(im.getAttribute('src')||'')).match(/u(\\d{1,2})/);
        if(!m) return;
        var tr=im.closest('tr');
        var ns=tr?(tr.textContent.match(/\\d+/g)||[]):[];
        out.push('u'+m[1]+' "'+((im.getAttribute('title')||im.getAttribute('alt')||'').substring(0,22))+'"'+(ns.length?' last='+ns[ns.length-1]:''));
        u++;
      });
      out.push('== ONCLICK ==');
      var oc=0;
      document.querySelectorAll('[onclick]').forEach(function(e){
        if(oc>=10) return;
        out.push(brief(e)+' '+(e.getAttribute('onclick')||'').substring(0,80));
        oc++;
      });
      return JSON.stringify({lines:out});
    })();
    """

    // MARK: - Helpers

    static func int(_ v: Any?) -> Int {
        if let n = v as? Int { return n }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)) ?? 0 }
        return 0
    }

    /// أسماء عربية معروفة للوحدات (fallback لو الصفحة ما وفرتش اسم).
    static func arabicUnitName(_ id: Int) -> String {
        switch id {
        case 1: return "الكتيبة الرومانية"
        case 2: return "الحرس الإمبراطوري"
        case 3: return "الجنود الإمبراطوريون"
        case 4: return "جواسيس الرومان"
        case 5: return "فرسان الإمبراطورية"
        case 6: return "فرسان قيصر"
        case 7: return "الكبش الروماني"
        case 8: return "المقلاع الناري"
        case 9: return "السيناتور"
        case 10: return "المستوطن الروماني"
        case 11: return "مقاتل بهراوة"
        case 12: return "مقاتل برمح"
        case 13: return "مقاتل بفأس"
        case 14: return "الكشاف"
        case 15: return "القيصر"
        case 16: return "فرسان التوتون"
        case 17: return "الكبش التوتوني"
        case 18: return "المقلاع"
        case 19: return "الرئيس"
        case 20: return "المستوطن التوتوني"
        case 21: return "الفرالكس"
        case 22: return "المبارز"
        case 23: return "المستكشف"
        case 24: return "رعد التوتون"
        case 25: return "فارس التنين"
        case 26: return "رأس الهود"
        case 27: return "الكبش الغالي"
        case 28: return "المقلاع الحربي"
        case 29: return "زعيم القرية"
        case 30: return "المستوطن الغالي"
        default: return "جندي"
        }
    }
}
