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
        UD.set(isAutomationEnabled, forKey: "automationOn")
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
        advancePendingAction()
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
        if autoSpyEnabled {
            autoSpyNext()
        }
        checkAlertAndRetreat()
    }

    /// التجسس التلقائي: كل دورة تجسس للقرية اللي بعد الحالي (دورياً).
    private var spyCursor = 0
    private func autoSpyNext() {
        guard pendingAction == nil else { return }
        guard !mapVillages.isEmpty else {
            logActivity("🤖 التجسس التلقائي: محتاج قرى بإحداثيات — من الخريطة أو اكتبها يدوي")
            return
        }
        // تجاهل القرى اللي مالهاش إحداثيات
        var target: MapVillage?
        for _ in 0..<mapVillages.count {
            spyCursor = (spyCursor + 1) % mapVillages.count
            let v = mapVillages[spyCursor]
            if v.x != 0 || v.y != 0 { target = v; break }
        }
        guard let t = target else {
            logActivity("🤖 مفيش قرى بإحداثيات صالحة لسه")
            return
        }
        logActivity("🤖 تجسس تلقائي على: \(t.name) (\(t.x)|\(t.y))")
        startSpy(x: t.x, y: t.y, name: t.name)
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
                let oldCounts = Dictionary(self.homeTroops.map { ($0.id, $0.count) }, uniquingKeysWith: { a, _ in a })
                self.homeTroops = units.map { u in
                    var u = u
                    if u.name.isEmpty { u.name = GameEngine.arabicUnitName(u.id) }
                    if u.count == 0, let old = oldCounts[u.id] { u.count = old }
                    return u
                }
            }
        }

        // الوحدات القابلة للتدريب — نفحصها في أي صفحة (الثكنات ممكن يكون رابطها مختلف)
        engine.readTrainableUnits { [weak self] units in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if units.count != self.trainableUnits.count {
                    self.logActivity(units.isEmpty
                        ? "مفيش وحدات تدريب في الصفحة (\(kind))"
                        : "لقيت \(units.count) وحدة قابلة للتدريب في \(kind)")
                }
                self.trainableUnits = units
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
    func startRetreat(auto: Bool) {
        let troops = homeTroops.filter { $0.count > 0 }
        guard !troops.isEmpty else {
            logActivity("❌ الهروب: مفيش بيانات جنود — افتح القرية (القرى) الأول")
            return
        }
        guard retreatX != 0 || retreatY != 0 else {
            logActivity("❌ الهروب: سجّل إحداثيات واحة الهروب الأول")
            return
        }
        pendingAction = .retreat
        actionStartedAt = Date()
        logActivity(auto ? "🏃 إنذار! بجهز الهروب بكل الجنود لـ (\(retreatX)|\(retreatY))..." : "🏃 تجهيز هروب تجريبي...")
        navigateToRallyPoint()
    }

    private func navigateToRallyPoint() {
        guard let url = URL(string: "https://utatar.com/a2b") else { return }
        webView?.load(URLRequest(url: url))
    }

    /// بيتم ناداه بعد ما أي صفحة تخلص تحميل — قراءة + تنفيذ المهمة المعلقة.
    func handlePageLoaded() {
        refreshGameData()
        advancePendingAction()
        recordCurrentPageIfNeeded()
    }

    /// مسجل الصفحات الأوتوماتيكي: يسجل كل صفحة جديدة (بدون تكرار) عشان نحلل الـ DOM الحقيقي.
    func recordCurrentPageIfNeeded() {
        guard let url = webView?.url?.absoluteString else { return }
        let base = url.components(separatedBy: "?").first ?? url
        let lastBase = lastRecordedURL.components(separatedBy: "?").first ?? lastRecordedURL
        guard base != lastBase else { return }
        lastRecordedURL = url
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
            let pairs = homeTroops.map { ($0.id, $0.count) }
            engine.sendTroops(x: retreatX, y: retreatY, units: pairs, mode: 1) { [weak self] ok, msg in
                DispatchQueue.main.async {
                    self?.logActivity(ok ? "🏃 \(msg) — الهروب انطلق لـ (\(self?.retreatX ?? 0)|\(self?.retreatY ?? 0))" : "❌ الهروب فشل: \(msg)")
                    if ok {
                        self?.sendNotification(title: "🏃 هروب", body: "الجنود في الطريق لوجهة الهروب")
                    }
                }
            }
        }
    }

    /// فحص إنذار الهجوم (بيشتغل على صفحات القرية بس) + الهروب التلقائي.
    private func checkAlertAndRetreat() {
        guard autoRetreatEnabled, pendingAction == nil else { return }
        guard pageKind == "dorf1" || pageKind == "dorf2" else { return }
        engine.readAlert { [weak self] hits in
            guard let self = self, !hits.isEmpty else { return }
            DispatchQueue.main.async {
                self.logActivity("⚠️ رصدت علامة تنبيه: \(hits.joined(separator: "، "))")
                if self.autoRetreatEnabled {
                    self.startRetreat(auto: true)
                }
            }
        }
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
    
    func injectAutoTrain() {
        // تدريب أعمى بعدد محدد من كل نوع — بيشتغل على صفحة الثكنات مهما كان شكلها
        let c = autoTrainCount
        engine.trainBlind(count: c) { [weak self] msg in
            DispatchQueue.main.async {
                self?.logActivity("🤖 تدريب تلقائي: \(msg)")
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
