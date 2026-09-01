import Foundation
import UIKit
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
        if attackAlerts {
            checkForAttacks()
        }
        if resourceFullAlerts {
            checkResourcesFull()
        }
        if autoSpyEnabled {
            exploreAndSpy()
        }
        checkAlertAndRetreat()
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
                // لقينا فورمة تدريب في صفحة build؟ سجّل عنوانها — دي الثكنة/الإسطبل اللي بندرّب فيها
                if !units.isEmpty, kind == "build", let url = self.webView?.url {
                    self.barracksPath = Self.trainablePath(from: url)
                }
                // اللقط الدائم: أي أنواع جديدة تظهر → تتخزن للأبد
                self.captureTroopTypes(units)
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
        lastBotNavAt = Date()
        webView?.load(URLRequest(url: url))
        markSubmitBusy()
    }

    /// بيتم ناداه بعد ما أي صفحة تخلص تحميل — قراءة + تنفيذ المهمة المعلقة.
    func handlePageLoaded() {
        refreshGameData()
        advancePendingAction()
        recordCurrentPageIfNeeded()
        // البوت وصل لصفحة مبنية بعد تنقل هو نفسه عمله؟ يدرب حالا (من غير انتظار الفترة)
        if isAutomationEnabled, autoTrainTroops, pendingAction == nil, pageKind == "build",
           Date().timeIntervalSince(lastBotNavAt) < 20 {
            injectAutoTrain(force: true)
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
        engine.readAlert { [weak self] incoming, hits in
            guard let self = self, incoming, !hits.isEmpty else { return }
            DispatchQueue.main.async {
                guard self.autoRetreatEnabled, self.pendingAction == nil else { return }
                self.logActivity("🚨 هجوم جاي على القرية! (\(hits.joined(separator: "، "))) — بجهز الهروب")
                self.startRetreat(auto: true)
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
        var pairs: [(String, Int)] = []
        for u in catalog {
            let raw = (trainCounts[u.id] ?? "").filter { $0.isNumber }
            if let n = Int(raw), n > 0 { pairs.append((u.id, n)) }
        }
        guard !pairs.isEmpty else {
            if !barracksHintShown {
                barracksHintShown = true
                logActivity("🐴 اكتب العدد جنب كل نوع عايز تدربه (أي رقم كتابي — 100 أو 1000000)")
            }
            return
        }
        if pageKind == "build" {
            fireTraining(pairs)
        } else if !barracksPath.isEmpty {
            if !barracksHintShown {
                barracksHintShown = true
                logActivity("🐴 التدريب المستمر: رايح الثكنة (\(barracksPath))")
            }
            navigate(path: barracksPath)
        } else {
            gotoBarracks(failReason: "التدريب المستمر محتاج الثكنة")
        }
    }

    /// تنفيذ التدريب الفعلي + ضبط الفترة الجاية + التحقق من قبول اللعبة.
    private func fireTraining(_ pairs: [(String, Int)]) {
        engine.trainSelected(pairs) { [weak self] ok, msg in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if ok {
                    if let url = self.webView?.url {
                        self.barracksPath = Self.trainablePath(from: url)
                    }
                    self.barracksHintShown = false
                    self.intervalNoteShown = false
                    self.ensureTrainQueued(withinMinutes: self.trainIntervalMin)
                    self.markSubmitBusy()
                    self.logActivity("🐴 تدريب مجدول: \(msg) — طلبت تاني بعد \(self.trainIntervalMin) دقيقة ✅")
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
                } else if msg.contains("مش كفاية") {
                    // الموارد خلصت: نعيد الجدولة بصمت — من غير تنقل ولا رفرش. الدورة الجاية هتجرب تاني.
                    self.ensureTrainQueued(withinMinutes: max(1, min(self.trainIntervalMin, 5)))
                    if Date().timeIntervalSince(self.lastShortageLogAt) > 120 {
                        self.lastShortageLogAt = Date()
                        let mins = max(1, min(self.trainIntervalMin, 5))
                        self.logActivity("🌵 \(msg) — في محاولة تانية بعد \(mins) دقيقة ✅")
                    }
                } else {
                    self.gotoBarracks(failReason: msg)
                }
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
        let newIds = Set(units.map { $0.id })
        let oldIds = Set(savedTroopTypes.compactMap { $0["id"] as? String })
        guard newIds != oldIds else { return }
        savedTroopTypes = Self.encodeUnits(units)
        logActivity("🎒 لقطت \(units.count) نوع جنود وحفظتهم دايمًا — تقدر تحدد اللي تحبه وتكتب العدد")
    }

    private static func encodeUnits(_ units: [TrainableUnit]) -> [[String: Any]] {
        units.map { ["id": $0.id, "name": $0.name, "max": $0.max, "costW": $0.costWood, "costC": $0.costClay, "costI": $0.costIron, "costCr": $0.costCrop] as [String: Any] }
    }

    private static func decodeUnits(_ arr: [[String: Any]]) -> [TrainableUnit] {
        arr.compactMap { d in
            guard let id = d["id"] as? String else { return nil }
            var u = TrainableUnit(id: id, name: d["name"] as? String ?? "")
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

    func navigate(path: String) {
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
