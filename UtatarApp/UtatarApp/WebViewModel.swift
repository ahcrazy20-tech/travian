import Foundation
import WebKit
import Combine
import UserNotifications

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
    private var pendingSpyVillage: MapVillage?

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
        refreshGameData()

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

    // MARK: - القراءة الحقيقية من اللعبة (GameEngine)

    /// بيشتغل بعد كل تحميل صفحة وكل دورة أوتوماتك:
    /// بيقرا الموارد والجنود والوحدات القابلة للتدريب من الـ DOM الحقيقي.
    func refreshGameData() {
        guard let urlString = webView?.url?.absoluteString else { return }
        let kind = GameEngine.pageKind(from: urlString)
        pageKind = kind

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
                let oldCounts = Dictionary(self.homeTroops.map { ($0.id, $0.count) }, uniquingKeysWith: { a, _ in a })
                self.homeTroops = units.map { u in
                    var u = u
                    if u.name.isEmpty { u.name = GameEngine.arabicUnitName(u.id) }
                    if u.count == 0, let old = oldCounts[u.id] { u.count = old }
                    return u
                }
            }
        }

        if kind == "training" {
            engine.readTrainableUnits { [weak self] units in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.trainableUnits = units
                }
            }
        } else {
            if !trainableUnits.isEmpty {
                trainableUnits = []
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
                }
                self.isScanningMap = false
                if self.mapVillages.isEmpty {
                    self.gameLog = "افتح صفحة الخريطة (karte.php) عشان أمسح القرى"
                } else {
                    self.gameLog = "لقينا \(self.mapVillages.count) قرية على الخريطة"
                }
            }
        }
    }

    /// التجسس على قرية: نفتح صفحتها ← نكمل آلياً لإرسال جواسيس بعد التحميل.
    func startSpy(_ village: MapVillage, scoutCount: Int = 3) {
        guard let webView = webView else { return }
        pendingSpyVillage = village
        gameLog = "🕵️ جاري الذهاب إلى \(village.name)..."
        if let url = URL(string: absoluteGameHref(village.href)) {
            webView.load(URLRequest(url: url))
        }
    }

    /// بيتم ناداه بعد ما أي صفحة تخلص تحميل — بيكمل خطوات التجسس الآلية.
    func handlePageLoaded() {
        refreshGameData()
        advanceSpyIfNeeded()
    }

    private func advanceSpyIfNeeded() {
        guard let target = pendingSpyVillage else { return }
        switch pageKind {
        case "villageInfo":
            gameLog = "🕵️ فتحنا \(target.name)... بنروح لنقطة التجمع"
            engine.clickSendTroopsFromVillageInfo { [weak self] clicked in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if !clicked {
                        self.pendingSpyVillage = nil
                        self.gameLog = "مش لاقي زر إرسال جنود في صفحة القرية — جرب من الخريطة تاني"
                    }
                }
            }
        case "a2b":
            engine.sendScouts(count: 3) { [weak self] ok, msg in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.pendingSpyVillage = nil
                    self.gameLog = ok ? "✅ \(msg) — استنى التقرير في berichte.php" : "❌ \(msg)"
                    if ok {
                        self.sendNotification(title: "🕵️ تجسس", body: "الجواسيس في الطريق — التقرير هيظهر في التقارير")
                    }
                }
            }
        default:
            break
        }
    }

    /// يحوّل رابط نسبي (/dorf1.php) لرابط كامل على سيرفر اللعبة.
    private func absoluteGameHref(_ href: String) -> String {
        if href.hasPrefix("http") { return href }
        if href.hasPrefix("/") { return "https://utatar.com" + href }
        if href.isEmpty { return gameURL }
        return "https://utatar.com/" + href
    }

    /// يفتح صفحة الخريطة عشان نقدر نمسح القرى.
    func openMap() {
        guard let url = URL(string: "https://utatar.com/karte.php") else { return }
        webView?.load(URLRequest(url: url))
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
    
    func injectAutoTrain() {
        let js = """
        (function() {
            try {
                // Auto train troops if barracks is available
                var trainBtns = document.querySelectorAll('.train_btn, [class*="train"], .recruit_btn');
                var trainInput = document.querySelector('.train_count, [class*="train_count"], input[name*="troop"]');
                
                if (trainBtns.length > 0 && trainInput) {
                    // Set train count to max available
                    var maxBtn = document.querySelector('.max_btn, [class*="max"]');
                    if (maxBtn) {
                        maxBtn.click();
                    }
                    
                    // Click train button
                    setTimeout(function() {
                        trainBtns[0].click();
                    }, 500);
                    
                    return 'training_started';
                }
                
                return 'no_barracks_available';
            } catch(e) {
                return 'error: ' + e.message;
            }
        })();
        """
        
        webView?.evaluateJavaScript(js) { result, error in
            if let result = result as? String, result.contains("training_started") {
                self.sendNotification(title: "⚔️ تدريب تلقائي", body: "بدأنا تدريب جنود جداد!")
            }
        }
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
