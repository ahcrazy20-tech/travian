import Foundation
import WebKit
import Combine
import UserNotifications

// MARK: - Troop Type
// A troop unit discovered on the current page (e.g. in the barracks).
struct TroopType: Identifiable, Equatable {
    let id: String
    var name: String
    var icon: String
    var max: Int          // max trainable (from input max), 0 if unknown
    var index: Int        // ordinal in the discovered list (used to find the input again)
    var inputName: String // the input name/id when known
    var selectedCount: Int // how many the user wants to train
}

class WebViewModel: NSObject, ObservableObject {
    @Published var isLoading = true
    @Published var currentURL: String = ""
    @Published var showAlert = false
    @Published var alertMessage = ""
    @Published var isAutomationEnabled = false

    // Automation settings
    @Published var autoCollectResources = false
    @Published var autoBuildQueue = false
    @Published var autoTrainTroops = false
    @Published var attackAlerts = true
    @Published var resourceFullAlerts = true
    @Published var buildCompleteAlerts = true

    // Game state
    @Published var woodAmount: String = "0"
    @Published var clayAmount: String = "0"
    @Published var ironAmount: String = "0"
    @Published var wheatAmount: String = "0"
    @Published var wheatProduction: String = "0"

    // Discovered troops & page diagnostics
    @Published var discoveredTroops: [TroopType] = []
    @Published var isInspecting = false
    @Published var inspectionLog: String = ""
    @Published var lastScanMessage: String = ""
    @Published var jsConsoleResult: String = ""

    var webView: WKWebView?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    let gameURL = "https://utatar.com/sign"

    override init() {
        super.init()
        setupTimer()
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
        if isAutomationEnabled {
            startAutomation()
            sendNotification(title: "أوتوماتك شغّال", body: "المساعد الأوتوماتك شغّال دلوقتي 🎮")
        } else {
            stopAutomation()
            sendNotification(title: "أوتوماتك واقف", body: "المساعد الأوتوماتك اتقفل")
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
        // Collect game state
        collectGameState()

        // Run enabled automations
        if autoCollectResources {
            injectAutoCollect()
        }
        if autoBuildQueue {
            injectAutoBuild()
        }
        if autoTrainTroops {
            injectAutoTrain()
        }
        if attackAlerts {
            checkForAttacks()
        }
        if resourceFullAlerts {
            checkResourcesFull()
        }
    }

    // MARK: - Page detection (resources + troops) via heuristics

    // Runs a generic DOM scan. Returns resource amounts + candidate troop rows
    // + a small input dump (for debugging). Wrapped so it always returns JSON.
    private func buildDetectScript() -> String {
        return """
        (function() {
          var out = { resources:{}, troops:[], inputs:[], url: window.location.href };
          function intFrom(t){ if(t===null||t===undefined) return null; var n=parseInt(String(t).replace(/[^0-9]/g,''),10); return isNaN(n)?null:n; }

          // ---------- RESOURCES ----------
          var resourceSelectors = [
            {key:'wood',  sel:['#l1','.l1','[id*="wood"]','[class*="wood"]','.resource_wood','[data-res="wood"]','[data-resource="wood"]']},
            {key:'clay',  sel:['#l2','.l2','[id*="clay"]','[class*="clay"]','.resource_clay','[data-res="clay"]','[data-resource="clay"]']},
            {key:'iron',  sel:['#l3','.l3','[id*="iron"]','[class*="iron"]','.resource_iron','[data-res="iron"]','[data-resource="iron"]']},
            {key:'wheat', sel:['#l4','.l4','[id*="wheat"]','[class*="wheat"]','.resource_wheat','[data-res="wheat"]','[data-resource="wheat"]']}
          ];
          var labels = { wood:['خشب','wood'], clay:['طين','clay','أرض'], iron:['حديد','iron'], wheat:['قمح','wheat','حبوب','crop'] };
          resourceSelectors.forEach(function(rs){
            var found = null;
            for (var s=0; s<rs.sel.length; s++){
              try{ var el=document.querySelector(rs.sel[s]); if(el){ var n=intFrom(el.textContent); if(n!==null){found=n;break;} } }catch(e){}
            }
            if (found===null){
              try{
                var txt = document.body ? document.body.innerText : '';
                var ls = labels[rs.key];
                for (var i=0;i<ls.length;i++){
                  var re = new RegExp(ls[i]+'[^0-9]{0,12}([0-9][0-9,. ]{0,18})','i');
                  var m = txt.match(re);
                  if(m){ var n=intFrom(m[1]); if(n!==null){found=n;break;} }
                }
              }catch(e){}
            }
            if (found!==null) out.resources[rs.key]=found;
          });

          // ---------- TROOPS ----------
          var troops = [];
          var allInputs = document.querySelectorAll('input[type="text"], input[type="number"], input[type="tel"], input[type="range"], input:not([type])');
          var known = [
            {n:['الرمح','spear','spearman'],icon:'🏹'},
            {n:['السيف','sword','swordsman'],icon:'⚔️'},
            {n:['الفأس','axe','axeman'],icon:'🪓'},
            {n:['الرامي','archer','قوس','bow'],icon:'🏹'},
            {n:['الكشاف','scout','spy'],icon:'🔭'},
            {n:['فيلق','phalanx','درع'],icon:'🛡️'},
            {n:['الخيالة','cavalry','فارس','rider'],icon:'🐎'},
            {n:['المنجنيق','catapult','ram','حمل'],icon:'⚙️'},
            {n:['الشعب','رئيس','chief'],icon:'👑'}
          ];
          var ti=0;
          allInputs.forEach(function(inp){
            if (ti>=40) return;
            var idx=(inp.name||inp.id||'').toLowerCase();
            var max = intFrom(inp.getAttribute('max')) || intFrom(inp.getAttribute('data-max')) || 0;
            var looksLike = (max>0) || /^(t|unit|troop|u)\\d+/i.test(idx) || ((inp.className||'').indexOf('troop')>=0);
            if (!looksLike) return;
            var row = inp.closest('tr, li, form, div[class]');
            var tip = row ? (row.querySelector('img, [title], [data-name], [data-unit], [data-tooltip], a[title]')) : null;
            var nm = tip ? (tip.getAttribute('alt')||tip.getAttribute('title')||tip.getAttribute('data-name')||tip.getAttribute('data-unit')||tip.getAttribute('data-tooltip')||'') : '';
            if(!nm && row){ nm = (row.innerText||'').replace(/[0-9,. ]+/g,'').trim().slice(0,40); }
            var label = (nm||'').trim();
            var icon = '⚔️';
            if (label.length===0) label = 'نوع '+(ti+1);
            var check = (label+' '+(idx||'')).toLowerCase();
            for (var k=0;k<known.length;k++){
              for (var q=0;q<known[k].n.length;q++){
                if (check.indexOf(known[k].n[q])>=0){ icon=known[k].icon; break; }
              }
            }
            troops.push({ id:'troop_'+ti, name:label, icon:icon, max:max, index:ti, inputName:idx||'' });
            ti++;
          });
          out.troops = troops;

          // ---------- INPUT DUMP (debug) ----------
          var inputs = [];
          document.querySelectorAll('input,select').forEach(function(x){
            if(inputs.length>50) return;
            inputs.push({tag:x.tagName, name:x.name||'', id:x.id||'', cls:(x.className||'').toString().slice(0,30), type:x.type||'', max:(x.getAttribute&&x.getAttribute('max'))||'', value:(x.value||'').toString().slice(0,12)});
          });
          out.inputs = inputs;
          return JSON.stringify(out);
        })();
        """
    }

    // Collect & publish resource amounts (+ attacks / build-complete flags).
    func collectGameState() {
        let js = buildDetectScript()
        webView?.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }
            guard error == nil,
                  let jsonString = result as? String,
                  let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let resources = json["resources"] as? [String: Any] else {
                return
            }
            DispatchQueue.main.async {
                self.woodAmount = self.numStr(resources["wood"])
                self.clayAmount = self.numStr(resources["clay"])
                self.ironAmount = self.numStr(resources["iron"])
                self.wheatAmount = self.numStr(resources["wheat"])
            }
        }
    }

    // Discover candidate troop rows and publish them (used by the UI).
    func detectTroops() {
        let js = buildDetectScript()
        isInspecting = true
        lastScanMessage = "جاري فحص الصفحة..."
        webView?.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isInspecting = false
                if error != nil {
                    self.lastScanMessage = "خطأ: \(error!.localizedDescription)"
                    return
                }
                guard let jsonString = result as? String,
                      let data = jsonString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.lastScanMessage = "لم نستطع قراءة البيانات من الصفحة."
                    return
                }
                let troopArr = json["troops"] as? [[String: Any]] ?? []
                self.discoveredTroops = troopArr.enumerated().map { (i, t) in
                    TroopType(
                        id: t["id"] as? String ?? "troop_\(i)",
                        name: t["name"] as? String ?? "نوع \(i+1)",
                        icon: t["icon"] as? String ?? "⚔️",
                        max: t["max"] as? Int ?? 0,
                        index: (t["index"] as? Int) ?? i,
                        inputName: t["inputName"] as? String ?? "",
                        selectedCount: 0
                    )
                }
                let inputDump = json["inputs"] as? [[String: Any]] ?? []
                let resDump = json["resources"] as? [String: Any] ?? [:]
                var log = "العناصر المكتشفة:\n"
                log += "موارد: " + (resDump.isEmpty ? "لا شيء" : String(describing: resDump)) + "\n"
                for inp in inputDump {
                    log += "  [\(str(inp["tag"]))] name=\(str(inp["name"])) id=\(str(inp["id"])) type=\(str(inp["type"])) max=\(str(inp["max"])) value=\(str(inp["value"]))\n"
                }
                self.inspectionLog = log
                if self.discoveredTroops.isEmpty {
                    self.lastScanMessage = "لم نجد مدخلات جنود واضحة. افتح صفحة الثكنات ثم اضغط فحص، أو أرسل لي اللي فوق."
                } else {
                    self.lastScanMessage = "لقينا \(self.discoveredTroops.count) نوع! اختار وحدّد العدد."
                }
            }
        }
    }

    // Full diagnostic — updates resources + troops + logs the page structure.
    func inspectPage() {
        detectTroops()
    }

    private func numStr(_ v: Any?) -> String {
        if let n = v as? NSNumber { return "\(n)" }
        if let s = v as? String { return s.isEmpty ? "0" : s }
        return "0"
    }

    private func str(_ v: Any?) -> String {
        if let v = v { return String(describing: v) }
        return ""
    }

    // MARK: - Train selected troops

    func trainSelectedTroops() {
        let selected = discoveredTroops
            .filter { $0.selectedCount > 0 }
            .map { ($0.index, $0.selectedCount) }
        guard !selected.isEmpty else {
            lastScanMessage = "اختار نوع جنود وحدّد العدد الأول."
            return
        }
        var arr = "["
        for (i, pair) in selected.enumerated() {
            arr += "[\(pair.0),\(pair.1)]"
            if i < selected.count - 1 { arr += "," }
        }
        arr += "]"

        let js = """
        (function() {
          try {
            var selections = \(arr);
            var allInputs = document.querySelectorAll('input[type="text"], input[type="number"], input[type="tel"], input[type="range"], input:not([type])');
            var trainInputs = [];
            allInputs.forEach(function(inp){
              var idx=(inp.name||inp.id||'').toLowerCase();
              var max = parseInt(inp.getAttribute('max')||inp.getAttribute('data-max')||'0')||0;
              var looksLike = (max>0)||/^(t|unit|troop|u)\\d+/i.test(idx)||((inp.className||'').indexOf('troop')>=0);
              if(looksLike) trainInputs.push(inp);
            });
            var trained=0, log=[];
            selections.forEach(function(sel){
              var idx=sel[0], count=parseInt(sel[1])||0;
              if(count<=0) return;
              if(idx<0||idx>=trainInputs.length) return;
              var inp=trainInputs[idx];
              if(!inp) return;
              var proto = HTMLInputElement.prototype;
              var setter = Object.getOwnPropertyDescriptor(proto,'value').set;
              try {
                setter.call(inp, String(count));
              } catch(e) {
                inp.value = String(count);
              }
              inp.dispatchEvent(new Event('input',{bubbles:true}));
              inp.dispatchEvent(new Event('change',{bubbles:true}));
              var row = inp.closest('tr, li, form, div[class]');
              var btn=null;
              if(row){
                btn = row.querySelector('button[type="submit"], input[type="submit"], button, a[href*="train"], a[href*="build"], a[href*="recruit"], a[class*="train"], a[class*="recruit"], a[class*="build"], a[class*="troop"]');
              }
              if(btn){ (function(b, idx2){ setTimeout(function(){ try{ b.click(); }catch(e){} }, 150); })(btn, idx); }
              trained++; log.push('unit'+idx+':'+count);
            });
            return JSON.stringify({trained:trained, log:log});
          } catch(e) {
            return JSON.stringify({trained:-1, error:e.message});
          }
        })();
        """

        webView?.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }
            if error != nil {
                self.lastScanMessage = "خطأ أثناء التدريب: \(error!.localizedDescription)"
                return
            }
            guard let jsonString = result as? String,
                  let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self.lastScanMessage = "لم نستطع تنفيذ التدريب."
                return
            }
            let trained = (json["trained"] as? Int) ?? 0
            if trained > 0 {
                self.lastScanMessage = "✅ بدأنا تدريب \(trained) نوع جنود"
                self.sendNotification(title: "⚔️ تدريب جنود", body: "بدأنا تدريب \(trained) نوع جنود!")
            } else if (json["trained"] as? Int) == -1 {
                self.lastScanMessage = "خطأ في الجافاسكريبت: \(self.str(json["error"]))"
            } else {
                self.lastScanMessage = "مفيش حاجة اتدربت — تأكد إنك على صفحة الثكنات."
            }
        }
    }

    func injectAutoTrain() {
        trainSelectedTroops()
    }

    // MARK: - Auto collect

    func injectAutoCollect() {
        let js = """
        (function() {
            try {
                var collectBtn = document.querySelector('.collect_btn, [class*="collect"], .reward_collect, [class*="reinforce"]');
                if (collectBtn) {
                    collectBtn.click();
                    return 'collected';
                }
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

    // MARK: - Auto build

    func injectAutoBuild() {
        let js = """
        (function() {
            try {
                var buildQueue = document.querySelector('.build_queue, [class*="queue"], #building_queue');
                var upgradeBtns = document.querySelectorAll('.upgrade_btn, [class*="upgrade"], .build_btn, [class*="level_up"], a[href*="build.php"], a[href*="upgrade"]');
                var queueItems = document.querySelectorAll('.queue_item, [class*="queue_item"]');
                if (queueItems.length < 2 && upgradeBtns.length > 0) {
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

    // MARK: - Alerts

    func checkForAttacks() {
        let js = """
        (function() {
            try {
                var attacks = document.querySelectorAll('.incoming_attack, [class*="attack_warning"], .attack_row, [class*="incoming"]');
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
        self.jsConsoleResult = "جارِ التنفيذ..."
        webView?.evaluateJavaScript(script) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    self.jsConsoleResult = "JS خطأ: \(error.localizedDescription)"
                } else if let str = result as? String {
                    self.jsConsoleResult = str.count > 800 ? String(str.prefix(800)) : str
                } else if let res = result {
                    self.jsConsoleResult = "🔎 نتيجة: \(String(describing: res))"
                } else {
                    self.jsConsoleResult = "✅ تم التنفيذ (لا توجد نتيجة نصية)."
                }
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
