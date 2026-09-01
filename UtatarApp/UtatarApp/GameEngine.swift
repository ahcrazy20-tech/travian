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
        if path.hasPrefix("dorf3") { return "villageInfo" }
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
        if(!dm){ var d3=href.match(/dorf3\\?id=(\\d+)/); if(d3) dm=d3; }
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
      // 1) خلايا الخريطة من أي نوع: <area> بعنوان أو href، أي عنصر onclick فيه d=،
      //    أي عنصر عنوانه فيه إحداثيات (x|y)
      document.querySelectorAll('area[title], area[href*="d="]').forEach(function(a){
        push(a.getAttribute('href')||('karte?d=area'+a.getAttribute('title')), a.getAttribute('title')||'');
      });
      document.querySelectorAll('[onclick*="d="]').forEach(function(d){
        var oc=d.getAttribute('onclick')||'';
        var m=oc.match(/d=(\\d{3,})/);
        if(!m) return;
        push('karte?d='+m[1], d.getAttribute('title')||(d.textContent||'').trim());
      });
      document.querySelectorAll('[title*="("][title*="|"]').forEach(function(e){
        var ti=e.getAttribute('title')||'';
        if(ti.length<5 || ti.length>120) return;
        var dm=(e.getAttribute('data-href')||e.getAttribute('href')||e.getAttribute('onclick')||'').match(/d=(\\d{3,})/);
        var key='karte?d='+(dm?dm[1]:('t'+ti.length+'_'+ti.substring(0,12)));
        push(key, ti);
      });
      // 2) لينكات كلاسيكية
      document.querySelectorAll('a[href*="karte"], area[href*="karte"]').forEach(function(a){
        var h=a.getAttribute('href')||'';
        if(h.indexOf('d=')>=0) push(h, a.getAttribute('title')||(a.textContent||'').trim());
      });
      // 3) خلايا الخريطة في عصر التتار: روابط dorf3?id=NNNNNN (بدون عنوان)
      document.querySelectorAll('area[href*="dorf3?id="], a[href*="dorf3?id="]').forEach(function(a){
        push(a.getAttribute('href')||'', a.getAttribute('title')||(a.textContent||'').trim());
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

    /// الإرسال الموحد بإحداثيات: تجسس (كشاف) / هجوم / هروب (كل الجنود تعزيز).
    /// units = [(unitId, count)] — بيملأ t[id] أو tf[id] أيهم موجود في الفورم.
    func sendTroops(x: Int, y: Int, units: [(Int, Int)], mode: Int, completion: @escaping (Bool, String) -> Void) {
        runJSON(Self.sendTroopsJS(x: x, y: y, units: units, mode: mode)) { obj in
            let ok = (obj?["sent"] as? Bool) ?? false
            let msg = (obj?["message"] as? String) ?? ""
            completion(ok, msg)
        }
    }

    static func sendTroopsJS(x: Int, y: Int, units: [(Int, Int)], mode: Int) -> String {
        var arr = "["
        for (i, u) in units.enumerated() {
            arr += "[\(u.0),\(u.1)]"
            if i < units.count - 1 { arr += "," }
        }
        arr += "]"
        // الحقيقة من مصدر محرك EBDA T4 (اللي لعبتك مبنية عليه):
        // c=2 تعزيز — c=3 هجوم عادي — c=4 نهب. (ترافيان الأصلي: 1/2/3)
        // بنطابق بالنص الأول (الأنجح) وقيم محرك EBDA كبديل أخير.
        var labelRx = ""
        var modeVals: [Int]
        switch mode {
        case 3: labelRx = "\\u0646\\u0647\\u0628|\\u0633\\u0631\\u0642\\u0629|raid|plunder"; modeVals = [4, 3]
        case 2: labelRx = "\\u0647\\u062c\\u0648\\u0645|\\u0627\\u0639\\u062a\\u062f\\u0627\\u0621|attack"; modeVals = [3, 2]
        default: labelRx = "\\u062a\\u0639\\u0632\\u064a\\u0632|\\u062f\\u0639\\u0645|reinfor|support"; modeVals = [2, 1]
        }
        let mv = "[" + modeVals.map(String.init).joined(separator: ",") + "]"
        let rx = "\u{22}" + labelRx + "\u{22}"
        
        return """
        (function(){
          try{
            function pi(x){ var n=parseInt(String(x).replace(/[^0-9]/g,''),10); return isNaN(n)?0:n; }
            var form=null;
            // فورم الإرسال = فيها إحداثيات x و y
            document.querySelectorAll('form').forEach(function(f){
              if(!form && f.querySelector('input[name="x"]') && f.querySelector('input[name="y"]')) form=f;
            });
            if(!form){
              document.querySelectorAll('form').forEach(function(f){
                if(!form && f.querySelector('input[name^="t"]')) form=f;
              });
            }
            if(!form) return JSON.stringify({sent:false,message:'افتح نقطة التجمع (a2b) الأول'});
            function setVal(inp,v){
              var proto=HTMLInputElement.prototype;
              var setter=Object.getOwnPropertyDescriptor(proto,'value').set;
              try{ setter.call(inp,String(v)); }catch(e){ inp.value=String(v); }
              inp.dispatchEvent(new Event('input',{bubbles:true}));
              inp.dispatchEvent(new Event('change',{bubbles:true}));
            }
            var xi=form.querySelector('input[name="x"]');
            var yi=form.querySelector('input[name="y"]');
            if(xi&&yi){ setVal(xi,\(x)); setVal(yi,\(y)); }
            var pairs=\(arr);
            var filled=0, filledNames=[];
            pairs.forEach(function(p){
              if(p[1]<=0) return;
              var cands=['t'+p[0], 'tf['+p[0]+']', 't['+p[0]+']'];
              for(var i=0;i<cands.length;i++){
                var inp=form.querySelector('input[name="'+cands[i]+'"]');
                if(inp){ setVal(inp,p[1]); filled++; filledNames.push(cands[i]+'='+p[1]); break; }
              }
            });
            if(filled===0) return JSON.stringify({sent:false,message:'مفيش مدخلات للجنود المطلوبين في الفورم'});
            // اختيار نوع الهجوم: بالتسمية العربي/الإنجليزي الأول (أدق)، وبعدين قيم EBDA
            var modeVals=\(mv);
            var labelRx=new RegExp(\(rx), "i");
            var modeRadio=null;
            var radios=[];
            form.querySelectorAll('input[name="c"]').forEach(function(r){ radios.push(r); });
            function labelText(r){
              var l = r.closest ? r.closest('label') : null;
              var t = l ? (l.textContent||'') : '';
              if(!t){ var p=r.parentElement; t = p ? (p.textContent||'') : ''; }
              return t.trim();
            }
            for(var ri=0; ri<radios.length && !modeRadio; ri++){
              var tx=labelText(radios[ri]);
              if(tx && labelRx.test(tx)) modeRadio=radios[ri];
            }
            for(var mi=0; mi<modeVals.length && !modeRadio; mi++){
              for(var ri2=0; ri2<radios.length && !modeRadio; ri2++){
                if(parseInt(radios[ri2].value,10)===modeVals[mi]) modeRadio=radios[ri2];
              }
            }
            var viaLabel = !!(modeRadio && labelRx.test(labelText(modeRadio)));
            if(modeRadio){ modeRadio.click(); }
            // ===== التوأمة: محرك EBDA الأصلي بيقرا t1..t10 (موضعي: u14=t4)،
            // والنسخ المعدلة بتقرا t14 أو t[14] أو tf[14]. بنبعت كل الأشكال مع بعض —
            // الخادم بياخد اللي بيفهمه ويتجاهل الباقي، ومفيش أي ضرر من الحقول الزيادة.
            function twinNames(nm){
              var m=nm.match(/^tf?\\[?(\\d{1,2})\\]?$/);
              if(!m) return [];
              var n=parseInt(m[1],10);
              var keep={}; keep[nm]=1;
              var out={};
              out['t'+n]=1;                        // 14
              var pos=(n-1)%10+1; out['t'+pos]=1;  // موضعي: 14 -> t4
              out['t['+n+']']=1;                   // t[14]
              out['tf['+n+']']=1;                  // tf[14]
              for(var k in keep) delete out[k];
              return Object.keys(out);
            }
            var added=[];
            form.querySelectorAll('input[name]').forEach(function(inp){
              var nm=inp.getAttribute('name')||'';
              var v=parseInt(inp.value,10);
              if(!v || v<=0) return;
              twinNames(nm).forEach(function(tn){
                if(!form.querySelector('input[name="'+tn+'"]')){
                  var h=document.createElement('input');
                  h.setAttribute('type','hidden'); h.setAttribute('name',tn); h.setAttribute('value',String(v));
                  form.appendChild(h); added.push(tn+'='+v);
                }
              });
            });
            // s1=ok المخفي (المحرك الأصلي بيفحصه أحيانًا)
            if(!form.querySelector('input[name="s1"]')){
              var s1=document.createElement('input');
              s1.setAttribute('type','hidden'); s1.setAttribute('name','s1'); s1.setAttribute('value','ok');
              form.appendChild(s1);
            }
            var btn=form.querySelector('button[type="submit"], input[type="submit"], button:not([type])');
            if(btn){ btn.click(); }
            else if(form.requestSubmit){ form.requestSubmit(); }
            else { return JSON.stringify({sent:false,message:'لا يوجد زر إرسال'}); }
            return JSON.stringify({sent:true,message:'انطلقت القوات ('+filledNames.join(', ')+')'+(added.length?' +توائم('+added.slice(0,4).join(',')+')':'')+(viaLabel?' [بالنص]':' [بالقيمة]')});
          }catch(e){ return JSON.stringify({sent:false,message:e.message}); }
        })();
        """
    }

    /// التدريب الأعمى بعدد محدد: بيدور على أي فورم تدريب (t[11].. / tf[..]) في أي صفحة
    /// وبيملأ كل نوع بالعدد (مع احترام الحد الأقصى لو معروض) ويدرس.
    func trainBlind(count: Int, completion: @escaping (Bool, String) -> Void) {
        runJSON(Self.trainBlindJS(count: count)) { obj in
            let ok = (obj?["ok"] as? Bool) ?? false
            completion(ok, (obj?["message"] as? String) ?? (ok ? "تم" : "فشل"))
        }
    }

    /// بيدور على لينك الثكنة في الصفحة الحالية (نص/عنوان فيه "ثكنة") — عشان نوصلها أوتوماتك.
    func findBarracksLink(completion: @escaping (String?) -> Void) {
        runJSON(Self.findBarracksLinkJS) { obj in
            completion(obj?["href"] as? String)
        }
    }

    static let findBarracksLinkJS = """
    (function(){
      try{
        var links=document.querySelectorAll('a[href]');
        for(var i=0;i<links.length;i++){
          var a=links[i];
          var href=a.getAttribute('href')||'';
          if(!/^build\\?(id|bid)=\\d+/.test(href) && href.indexOf('build')<0) continue;
          var txt=((a.textContent||'')+' '+(a.getAttribute('title')||'')+' '+(a.className||''));
          var img=a.querySelector('img');
          if(img){ txt+=' '+(img.getAttribute('title')||'')+' '+(img.getAttribute('alt')||'')+' '+(img.getAttribute('class')||''); }
          if(txt.indexOf('ثكنة')>=0 || txt.indexOf('thkena')>=0 || /(^|\\s)g19(\\s|$)/.test(txt)){
            if(href.indexOf('http')!==0) href='https://utatar.com/'+href.replace(/^\\//,'');
            return JSON.stringify({href:href});
          }
        }
        return JSON.stringify({href:null});
      }catch(e){ return JSON.stringify({href:null}); }
    })();
    """


    static func trainBlindJS(count: Int) -> String {
        return """
        (function(){
          try{
            function isSendForm(f){ return f.querySelector('input[name="x"]') && f.querySelector('input[name="y"]'); }
            var form=null;
            document.querySelectorAll('form').forEach(function(f){
              if(form || isSendForm(f)) return;
              var act=f.getAttribute('action')||'';
              // فورم التدريب بيتبعت لـ build — فورم الإرجاع/الإرسال بتتبعت لـ a2b: منفضلش نمسها
              if(act.indexOf('a2b')>=0) return;
              var has=false;
              f.querySelectorAll('input[name]').forEach(function(i){
                var nm=i.getAttribute('name')||'';
                if(!has && (/^t(f)?\\[\\d+\\]$/.test(nm) || /^t\\d{1,2}$/.test(nm))) has=true;
              });
              if(has) form=f;
            });
            if(!form) return JSON.stringify({ok:false,message:'مفيش فورم تدريب في الصفحة دي'});
            function setVal(inp,v){
              var proto=HTMLInputElement.prototype;
              var setter=Object.getOwnPropertyDescriptor(proto,'value').set;
              try{ setter.call(inp,String(v)); }catch(e){ inp.value=String(v); }
              inp.dispatchEvent(new Event('input',{bubbles:true}));
              inp.dispatchEvent(new Event('change',{bubbles:true}));
            }
            var filled=0, names=[];
            form.querySelectorAll('input[name]').forEach(function(inp){
              var nm=inp.getAttribute('name')||'';
              if(!/^t(f)?\\[\\d+\\]$/.test(nm) && !/^t\\d{1,2}$/.test(nm)) return;
              var max=parseInt(inp.getAttribute('max'),10);
              var v=\(count);
              if(!isNaN(max)&&max>0&&v>max) v=max;
              setVal(inp,v);
              filled++; names.push(nm+'='+v);
            });
            if(filled===0) return JSON.stringify({ok:false,message:'مفيش حقول تدريب'});
            // ===== التوأمة للتدريب: المعالج الأصلي (Technology.php procTrain) بيقرا
            // t11..t20 من غير أقواس وبيشترط ft=t1 + id. بنضمن الحقول دي كلها موجودة.
            form.querySelectorAll('input[name]').forEach(function(inp){
              var nm=inp.getAttribute('name')||'';
              var v=parseInt(inp.value,10);
              if(!v || v<=0) return;
              var m=nm.match(/^t(f)?\\[(\\d{1,2})\\]$/);
              if(m){
                var plain='t'+m[2];
                if(!form.querySelector('input[name="'+plain+'"]')){
                  var h=document.createElement('input');
                  h.setAttribute('type','hidden'); h.setAttribute('name',plain); h.setAttribute('value',String(v));
                  form.appendChild(h); names.push(plain+'='+v);
                }
              }
            });
            if(!form.querySelector('input[name="ft"]')){
              var ft=document.createElement('input');
              ft.setAttribute('type','hidden'); ft.setAttribute('name','ft'); ft.setAttribute('value','t1');
              form.appendChild(ft);
            }
            if(!form.querySelector('input[name="id"]')){
              var idm=(location.pathname+location.search).match(/id=(\\d+)/);
              var idh=document.createElement('input');
              idh.setAttribute('type','hidden'); idh.setAttribute('name','id'); idh.setAttribute('value',idm?idm[1]:'34');
              form.appendChild(idh);
            }
            if(!form.querySelector('input[name="s1"]')){
              var s1=document.createElement('input');
              s1.setAttribute('type','hidden'); s1.setAttribute('name','s1'); s1.setAttribute('value','ok');
              form.appendChild(s1);
            }
            var btn=form.querySelector('button[type="submit"], input[type="submit"], button:not([type])');
            if(btn){ btn.click(); }
            else if(form.requestSubmit){ form.requestSubmit(); }
            else { return JSON.stringify({ok:false,message:'لا يوجد زر تدريب'}); }
            // لو التنقل بدأ فعلاً نمنع أي محاولة تانية (عشان ما نكررش التدريب)
            try{ window.addEventListener('pagehide', function(){ window.__utatarNav=true; }, {once:true}); }catch(e4){}
            // لو الـ JS بتاع اللعبة منع الإرسال الأول: نعيد المحاولة بإرسال أصلي حقيقي
            setTimeout(function(){
              try{
                if(!window.__utatarNav && document.body && document.body.contains(form)){
                  if(btn && form.requestSubmit){ form.requestSubmit(btn); }
                  else { btn ? btn.click() : (form.submit ? form.submit() : null); }
                }
              }catch(e3){}
            }, 1500);
            // بعد 4 ثواني: لو الفورم لسه موجود يبقى اللعبة رفضت فعلاً — نسجل ردها
            setTimeout(function(){
              try{
                var alive = document.body && document.body.contains(form);
                var errs='';
                document.querySelectorAll('[class*="error"],[class*="err"],[class*="alert"],[class*="notif"]').forEach(function(e){
                  var t2=(e.textContent||'').trim();
                  if(t2.length>0 && t2.length<160) errs += ' | '+t2;
                });
                window.__utatarTrainCheck = alive ? ('still'+errs) : 'gone';
              }catch(e2){}
            }, 4000);
            return JSON.stringify({ok:true,message:'بدأ التدريب ('+names.join(', ')+')'});
          }catch(e){ return JSON.stringify({ok:false,message:e.message}); }
        })();
        """
    }

    /// بعد التدريب: بيرجع إشارة التحقق (gone = الصفحة اتنقلت = اللعبة قبلت).
    func trainCheck(completion: @escaping (String) -> Void) {
        runJSON(Self.trainCheckJS) { obj in
            completion((obj?["state"] as? String) ?? "none")
        }
    }

    static let trainCheckJS = """
    (function(){
      try{ return JSON.stringify({state: String(window.__utatarTrainCheck||'none').substring(0,180)}); }
      catch(e){ return JSON.stringify({state:'none'}); }
    })();
    """

    /// قراءة صفحة معلومات القرية (dorf3/karte?d=): الاسم واللاعب والإحداثيات ولينك الهجوم.
    func readVillageInfo(completion: @escaping ([String: Any]?) -> Void) {
        runJSON(Self.readVillageInfoJS) { obj in completion(obj) }
    }

    static let readVillageInfoJS = """
    (function(){
      try{
        var b=document.body||document.querySelector('body');
        var txt=b?(b.textContent||''):'';
        function rx(re){ var m=txt.match(re); return m?m[1].trim():''; }
        var player=rx(/اللاعب\\s*:?\\s*([^\\n(]{2,30})/);
        var pop=rx(/السكان\\s*:?\\s*([0-9]+)/);
        var coords=txt.match(/\\((-?\\d{1,4})\\s*\\|\\s*(-?\\d{1,4})\\)/);
        var name='';
        var h=document.querySelector('h1,h2,.title,b');
        if(h) name=(h.textContent||'').trim();
        var a2b='';
        var al=document.querySelector('a[href*="a2b"]');
        if(al) a2b=al.getAttribute('href')||'';
        return JSON.stringify({name:name.substring(0,40), player:player, x:coords?parseInt(coords[1],10):0, y:coords?parseInt(coords[2],10):0, population:pop, a2b:a2b.substring(0,60)});
      }catch(e){ return JSON.stringify({player:'', x:0, y:0, error:e.message}); }
    })();
    """

    /// كاشف إنذار الهجوم: بيدور على أيقونات/عناصر التحذير الشائعة.
    func readAlert(completion: @escaping (Bool, [String]) -> Void) {
        runJSON(Self.alertJS) { obj in
            let inc = (obj?["incoming"] as? Bool) ?? false
            completion(inc, obj?["hits"] as? [String] ?? [])
        }
    }

    static let alertJS = """
    (function(){
      var hits=[];
      var incoming=false;
      // الحقيقة من مصدر المحرك (movement.tpl):
      // هجوم قادم عليك = <img class="att1"> + <span class="a1"> جوه div.movements
      // (att2/a2 = نهب قادم، att3 = راجعين). دي أدق إشارة ومصدرها كود اللعبة نفسه.
      var incomingSels=['.movements img.att1','#movements img.att1','.movements img.att2','#movements img.att2','.movements span.a1','.movements span.a2'];
      incomingSels.forEach(function(sel){
        try{
          var els=document.querySelectorAll(sel);
          if(els.length>0){ incoming=true; hits.push(sel+' x'+els.length); }
        }catch(e){}
      });
      // بدائل عامة (لو النسخة معدلة): عناصر تحذير معروفة
      var sels=['[class*="incoming"]','[class*="attack_warn"]','img[src*="alarm"]','[id*="alarm"]','img[src*="warn"]'];
      sels.forEach(function(sel){
        try{
          var els=document.querySelectorAll(sel);
          if(els.length>0){
            var t=(els[0].textContent||'').trim();
            if(/هجوم|att/i.test(t+' '+sel)) incoming=true;
            hits.push(sel+' x'+els.length);
          }
        }catch(e){}
      });
      return JSON.stringify({incoming:incoming,hits:hits});
    })();
    """

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

    // MARK: - المسجل التلقائي للصفحات

    func runPageRecord(completion: @escaping (String) -> Void) {
        runJSON(Self.pageRecordJS) { obj in
            let lines = obj?["lines"] as? [Any] ?? []
            let text = lines.compactMap { $0 as? String }.joined(separator: "\n")
            completion(text)
        }
    }

    static let pageRecordJS = """
    (function(){
      var out=[];
      out.push('URL: '+location.href);
      out.push('TITLE: '+(document.title||''));
      document.querySelectorAll('form').forEach(function(f,fi){
        var parts=[];
        f.querySelectorAll('input,button').forEach(function(i){
          if(parts.length>=14) return;
          var ty=i.getAttribute('type')||i.tagName.toLowerCase();
          var s=(i.getAttribute('name')||'?')+'/'+ty;
          var mx=i.getAttribute('max')||i.getAttribute('data-max');
          if(mx) s+='[max='+mx+']';
          if(ty=='radio'||ty=='checkbox'){
            s+='='+(i.getAttribute('value')||'?')+(i.checked?'*':'');
          } else if(ty=='hidden'){
            s+='='+(i.value||'').substring(0,20);
          } else if(ty=='text'||ty=='tel'){
            var v0=i.getAttribute('value');
            if(v0) s+='[val='+v0.substring(0,12)+']';
          }
          if(ty=='submit'||i.tagName.toLowerCase()=='button'){
            var tx=(i.textContent||i.value||'').trim();
            if(tx) s+='="'+tx.substring(0,15)+'"';
          }
          parts.push(s);
        });
        out.push('F'+fi+' '+(f.getAttribute('action')||'-')+' :: '+parts.join(' | '));
      });
      var u=0;
      document.querySelectorAll('img').forEach(function(im){
        if(u>=10) return;
        var m=((im.getAttribute('class')||'')+' '+(im.getAttribute('src')||'')).match(/u(\\d{1,2})/);
        if(m){ out.push('IMG u'+m[1]+' "'+((im.getAttribute('title')||im.getAttribute('alt')||'').substring(0,18))+'"'); u++; }
      });
      var seen={}, l=0;
      document.querySelectorAll('a[href]').forEach(function(a){
        if(l>=10) return;
        var h=a.getAttribute('href')||'';
        if(!/karte|map|a2b|build|berichte|spy|send|dorf|attack/.test(h)||seen[h]) return;
        seen[h]=1; out.push('A '+h.substring(0,70)); l++;
      });
      if(/karte|map/.test(location.href)){
        document.querySelectorAll('area').forEach(function(a,i){
          if(i>=6) return;
          out.push('AREA href='+(a.getAttribute('href')||'').substring(0,55)+' title="'+(a.getAttribute('title')||'').substring(0,40)+'"');
        });
        var oc=0;
        document.querySelectorAll('[onclick]').forEach(function(d){
          if(oc>=8) return;
          oc++;
          out.push('OC '+d.tagName+' '+(d.getAttribute('onclick')||'').substring(0,65)+' t="'+(d.getAttribute('title')||'').substring(0,25)+'"');
        });
      }
      // رسايل اللعبة الظاهرة (رفض تدريب/أخطاء/تنبيهات) — دليل مباشر على سبب الرفض
      var msg=0;
      document.querySelectorAll('[class*="error"],[class*="err "],[class*="alert"],[class*="notif"],[class*="message"],[id*="error"]').forEach(function(e){
        if(msg>=4) return;
        var t2=(e.textContent||'').trim();
        var vis = e.offsetWidth!==undefined ? (e.offsetWidth>0 && e.offsetHeight>0) : true;
        if(t2.length>2 && t2.length<160 && vis){ out.push('MSG: '+t2.replace(/\\s+/g,' ')); msg++; }
      });
      ['img[src*="alert"]','img[src*="warn"]','[id*="alarm"]','[class*="alarm"]'].forEach(function(sel){
        try{ var n=document.querySelectorAll(sel).length; if(n>0) out.push('ALERT? '+sel+' x'+n); }catch(e){}
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
        case 15: return "مقاتل القيصر"
        case 16: return "فرسان الجرمان"
        case 17: return "محطمة الابواب"
        case 18: return "المقلاع"
        case 19: return "الزعيم"
        case 20: return "مستوطن"
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
