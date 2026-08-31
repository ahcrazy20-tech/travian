import Foundation
import WebKit
import Combine
import UserNotifications

// MARK: - Village Data Model
struct VillageInfo: Identifiable, Codable {
    let id: String
    var name: String
    var x: Int
    var y: Int
    var distance: Double
    var population: Int
    var wood: Int
    var clay: Int
    var iron: Int
    var wheat: Int
    var totalResources: Int {
        return wood + clay + iron + wheat
    }
    var isRich: Bool {
        return totalResources > 1000
    }
    var lastScouted: Date?
    var hasTroops: Bool = false
    var troopCount: Int = 0
    var wallLevel: Int = 0
    var isOasis: Bool = false
    var owner: String = ""
}

// MARK: - Attack Target
struct AttackTarget: Identifiable {
    let id = UUID()
    let village: VillageInfo
    let estimatedLoot: Int
    let riskLevel: RiskLevel
    let recommendedTroops: Int
    
    enum RiskLevel: String {
        case easy = "🟢 سهل"
        case medium = "🟡 متوسط"
        case hard = "🔴 صعب"
    }
}

// MARK: - Farming Bot Settings
struct FarmingSettings: Codable {
    var isEnabled: Bool = false
    var autoScoutEnabled: Bool = true
    var autoAttackEnabled: Bool = false
    var minResourcesToAttack: Int = 500
    var maxDistance: Double = 20.0
    var scoutInterval: TimeInterval = 300 // 5 minutes
    var attackInterval: TimeInterval = 600 // 10 minutes
    var maxAttacksPerHour: Int = 10
    var avoidActivePlayers: Bool = true
    var avoidHighWall: Bool = true
    var maxWallLevel: Int = 5
    var useOnlyScouts: Bool = false
    var minTroopsToSend: Int = 1
    var maxTroopsToSend: Int = 20
    var saveReports: Bool = true
}

// MARK: - Spy & Attack Bot
class SpyAttackBot: ObservableObject {
    @Published var discoveredVillages: [VillageInfo] = []
    @Published var attackTargets: [AttackTarget] = []
    @Published var attackHistory: [AttackRecord] = []
    @Published var isScouting = false
    @Published var isAttacking = false
    @Published var scoutingProgress: Double = 0
    @Published var lastError: String?
    
    var farmingSettings = FarmingSettings()
    private var webView: WKWebView?
    private var scoutingTimer: Timer?
    private var attackTimer: Timer?
    private var attacksThisHour: Int = 0
    private var lastAttackReset: Date = Date()
    
    // MARK: - Setup
    
    func setup(webView: WKWebView) {
        self.webView = webView
    }
    
    // MARK: - Scouting (التجسس)
    
    func startScouting() {
        guard !isScouting else { return }
        isScouting = true
        scoutingProgress = 0
        
        // Start scouting nearby villages
        scoutNearbyVillages()
        
        // Setup periodic scouting
        scoutingTimer = Timer.scheduledTimer(withTimeInterval: farmingSettings.scoutInterval, repeats: true) { [weak self] _ in
            self?.scoutNearbyVillages()
        }
    }
    
    func stopScouting() {
        isScouting = false
        scoutingTimer?.invalidate()
        scoutingTimer = nil
    }
    
    private func scoutNearbyVillages() {
        let js = """
        (function() {
            try {
                var villages = [];
                
                // Method 1: Get villages from map view
                var mapVillages = document.querySelectorAll('.village_item, [class*="village"], .map_village, [class*="map_point"]');
                mapVillages.forEach(function(v, index) {
                    if (index < 50) { // Limit to 50 villages
                        var name = v.querySelector('.village_name, [class*="name"]');
                        var coords = v.querySelector('.coordinates, [class*="coord"]');
                        var pop = v.querySelector('.population, [class*="pop"]');
                        var res = v.querySelector('.resources, [class*="resource"]');
                        
                        villages.push({
                            id: 'village_' + index,
                            name: name ? name.textContent.trim() : 'Unknown',
                            x: 0,
                            y: 0,
                            population: pop ? parseInt(pop.textContent) || 0 : 0,
                            wood: 0,
                            clay: 0,
                            iron: 0,
                            wheat: 0,
                            hasTroops: false,
                            troopCount: 0,
                            wallLevel: 0
                        });
                    }
                });
                
                // Method 2: Get from rally point / map
                var mapPoints = document.querySelectorAll('.map_point, [class*="tile"], .tile');
                mapPoints.forEach(function(point, index) {
                    if (index < 100) {
                        var info = point.querySelector('.tip, [title], [data-title]');
                        var title = info ? (info.getAttribute('title') || info.getAttribute('data-title') || '') : '';
                        
                        if (title.length > 0) {
                            villages.push({
                                id: 'map_' + index,
                                name: title.substring(0, 30),
                                x: 0,
                                y: 0,
                                population: 0,
                                wood: 0,
                                clay: 0,
                                iron: 0,
                                wheat: 0,
                                hasTroops: false,
                                troopCount: 0,
                                wallLevel: 0
                            });
                        }
                    }
                });
                
                // Method 3: Parse current page for village info
                var currentInfo = document.querySelector('.village_info, [class*="villageInfo"], #village_info');
                if (currentInfo) {
                    var resources = currentInfo.querySelectorAll('.resource, [class*="resource"]');
                    var resValues = [];
                    resources.forEach(function(r) {
                        var val = parseInt(r.textContent.replace(/[^0-9]/g, ''));
                        if (!isNaN(val)) resValues.push(val);
                    });
                    
                    if (resValues.length >= 4) {
                        villages.push({
                            id: 'current',
                            name: 'القرية الحالية',
                            x: 0,
                            y: 0,
                            population: 0,
                            wood: resValues[0] || 0,
                            clay: resValues[1] || 0,
                            iron: resValues[2] || 0,
                            wheat: resValues[3] || 0,
                            hasTroops: false,
                            troopCount: 0,
                            wallLevel: 0
                        });
                    }
                }
                
                return JSON.stringify({
                    success: true,
                    villages: villages,
                    count: villages.length,
                    url: window.location.href
                });
            } catch(e) {
                return JSON.stringify({success: false, error: e.message});
            }
        })();
        """
        
        webView?.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }
            
            if let jsonString = result as? String,
               let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let success = json["success"] as? Bool, success,
               let villagesArray = json["villages"] as? [[String: Any]] {
                
                DispatchQueue.main.async {
                    self.processScoutedVillages(villagesArray)
                    self.scoutingProgress = min(1.0, self.scoutingProgress + 0.1)
                }
            }
        }
    }
    
    private func processScoutedVillages(_ villagesData: [[String: Any]]) {
        for data in villagesData {
            guard let id = data["id"] as? String else { continue }
            
            let village = VillageInfo(
                id: id,
                name: data["name"] as? String ?? "Unknown",
                x: data["x"] as? Int ?? 0,
                y: data["y"] as? Int ?? 0,
                distance: data["distance"] as? Double ?? 0,
                population: data["population"] as? Int ?? 0,
                wood: data["wood"] as? Int ?? 0,
                clay: data["clay"] as? Int ?? 0,
                iron: data["iron"] as? Int ?? 0,
                wheat: data["wheat"] as? Int ?? 0,
                lastScouted: Date(),
                hasTroops: data["hasTroops"] as? Bool ?? false,
                troopCount: data["troopCount"] as? Int ?? 0,
                wallLevel: data["wallLevel"] as? Int ?? 0
            )
            
            // Update or add village
            if let index = discoveredVillages.firstIndex(where: { $0.id == id }) {
                discoveredVillages[index] = village
            } else {
                discoveredVillages.append(village)
            }
        }
        
        // Update attack targets
        updateAttackTargets()
    }
    
    // MARK: - Target Analysis (تحليل الأهداف)
    
    private func updateAttackTargets() {
        attackTargets = discoveredVillages.compactMap { village in
            analyzeTarget(village)
        }.sorted { $0.estimatedLoot > $1.estimatedLoot }
    }
    
    private func analyzeTarget(_ village: VillageInfo) -> AttackTarget? {
        // Skip if not enough resources
        guard village.totalResources >= farmingSettings.minResourcesToAttack else { return nil }
        
        // Skip if too far
        guard village.distance <= farmingSettings.maxDistance else { return nil }
        
        // Skip if high wall
        if farmingSettings.avoidHighWall && village.wallLevel > farmingSettings.maxWallLevel {
            return nil
        }
        
        // Calculate risk level
        let riskLevel: AttackTarget.RiskLevel
        if village.hasTroops && village.troopCount > 10 {
            riskLevel = .hard
        } else if village.hasTroops || village.wallLevel > 3 {
            riskLevel = .medium
        } else {
            riskLevel = .easy
        }
        
        // Skip hard targets if avoiding active players
        if farmingSettings.avoidActivePlayers && riskLevel == .hard {
            return nil
        }
        
        // Calculate recommended troops
        let baseTroops = max(farmingSettings.minTroopsToSend, village.totalResources / 100)
        let recommendedTroops = min(farmingSettings.maxTroopsToSend, baseTroops + (village.hasTroops ? 5 : 0))
        
        return AttackTarget(
            village: village,
            estimatedLoot: village.totalResources,
            riskLevel: riskLevel,
            recommendedTroops: recommendedTroops
        )
    }
    
    // MARK: - Auto Attack (هجوم تلقائي)
    
    func startAutoAttack() {
        guard farmingSettings.autoAttackEnabled else { return }
        guard !isAttacking else { return }
        
        isAttacking = true
        
        // Reset attack counter every hour
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.attacksThisHour = 0
            self?.lastAttackReset = Date()
        }
        
        // Start attack cycle
        attackTimer = Timer.scheduledTimer(withTimeInterval: farmingSettings.attackInterval, repeats: true) { [weak self] _ in
            self?.executeAttackCycle()
        }
        
        // Execute first attack immediately
        executeAttackCycle()
    }
    
    func stopAutoAttack() {
        isAttacking = false
        attackTimer?.invalidate()
        attackTimer = nil
    }
    
    private func executeAttackCycle() {
        guard attacksThisHour < farmingSettings.maxAttacksPerHour else {
            print("⚠️ Reached max attacks per hour: \(farmingSettings.maxAttacksPerHour)")
            return
        }
        
        guard let target = attackTargets.first else {
            print("⚠️ No targets available")
            return
        }
        
        sendAttack(to: target)
    }
    
    private func sendAttack(to target: AttackTarget) {
        let troopCount = target.recommendedTroops
        let villageId = target.village.id
        
        let js = """
        (function() {
            try {
                // Navigate to rally point
                var rallyPoint = document.querySelector('a[href*="build.php?id=39"], a[href*="rally"], [class*="rally_point"]');
                if (rallyPoint) {
                    rallyPoint.click();
                }
                
                // Wait for page load then fill attack form
                setTimeout(function() {
                    // Set target coordinates
                    var xInput = document.querySelector('input[name="x"], input[name="coord_x"], #xCoordInput');
                    var yInput = document.querySelector('input[name="y"], input[name="coord_y"], #yCoordInput');
                    
                    if (xInput) xInput.value = '\(target.village.x)';
                    if (yInput) yInput.value = '\(target.village.y)';
                    
                    // Set troop count
                    var troopInput = document.querySelector('input[name*="troop"], input[name*="t1"], .troop_input');
                    if (troopInput) {
                        troopInput.value = '\(troopCount)';
                    }
                    
                    // Select attack type (raid/normal)
                    var raidOption = document.querySelector('input[value="4"], input[name="type"][value="4"], .raid_option');
                    if (raidOption) {
                        raidOption.click();
                    }
                    
                    // Click send button
                    setTimeout(function() {
                        var sendBtn = document.querySelector('#btn_send, .send_button, input[type="submit"], button[type="submit"]');
                        if (sendBtn) {
                            sendBtn.click();
                            return JSON.stringify({success: true, message: 'Attack sent to \(target.village.name)'});
                        }
                        return JSON.stringify({success: false, message: 'Send button not found'});
                    }, 500);
                    
                }, 1000);
                
                return JSON.stringify({success: true, message: 'Preparing attack...'});
            } catch(e) {
                return JSON.stringify({success: false, error: e.message});
            }
        })();
        """
        
        webView?.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }
            
            if let jsonString = result as? String,
               let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let success = json["success"] as? Bool, success {
                
                DispatchQueue.main.async {
                    self.attacksThisHour += 1
                    
                    // Record attack
                    let record = AttackRecord(
                        targetVillage: target.village.name,
                        troopsSent: troopCount,
                        timestamp: Date(),
                        estimatedLoot: target.estimatedLoot,
                        result: .pending
                    )
                    self.attackHistory.append(record)
                    
                    // Send notification
                    self.sendNotification(
                        title: "⚔️ هجوم تم إرساله!",
                        body: "هجوم على \(target.village.name) بـ \(troopCount) جندي"
                    )
                    
                    // Remove target from list
                    self.attackTargets.removeAll { $0.village.id == target.village.id }
                }
            }
        }
    }
    
    // MARK: - Village Scanning (فحص القرى بالتفصيل)
    
    func scanVillageDetails(_ village: VillageInfo, completion: @escaping (VillageInfo?) -> Void) {
        let js = """
        (function() {
            try {
                // Click on village to open details
                var villageLink = document.querySelector('a[href*="karte.php?x=\(village.x)&y=\(village.y)"], [data-x="\(village.x)"][data-y="\(village.y)"]');
                if (villageLink) {
                    villageLink.click();
                }
                
                // Wait for details to load
                setTimeout(function() {
                    var details = {
                        name: '',
                        population: 0,
                        wood: 0,
                        clay: 0,
                        iron: 0,
                        wheat: 0,
                        hasTroops: false,
                        troopCount: 0,
                        wallLevel: 0,
                        buildings: []
                    };
                    
                    // Get village name
                    var nameEl = document.querySelector('.village_name, h1, .title');
                    if (nameEl) details.name = nameEl.textContent.trim();
                    
                    // Get population
                    var popEl = document.querySelector('.population, [class*="pop"]');
                    if (popEl) details.population = parseInt(popEl.textContent) || 0;
                    
                    // Get resources
                    var resElements = document.querySelectorAll('.resource, [class*="resource"]');
                    var resValues = [];
                    resElements.forEach(function(r) {
                        var val = parseInt(r.textContent.replace(/[^0-9]/g, ''));
                        if (!isNaN(val)) resValues.push(val);
                    });
                    
                    if (resValues.length >= 4) {
                        details.wood = resValues[0];
                        details.clay = resValues[1];
                        details.iron = resValues[2];
                        details.wheat = resValues[3];
                    }
                    
                    // Get troop info
                    var troopEl = document.querySelectorAll('.troop, [class*="troop"], .unit');
                    details.hasTroops = troopEl.length > 0;
                    details.troopCount = troopEl.length;
                    
                    // Get wall level
                    var wallEl = document.querySelector('.wall, [class*="wall"]');
                    if (wallEl) {
                        var wallText = wallEl.textContent;
                        var wallMatch = wallText.match(/\\d+/);
                        details.wallLevel = wallMatch ? parseInt(wallMatch[0]) : 0;
                    }
                    
                    // Get buildings list
                    var buildingEls = document.querySelectorAll('.building, [class*="building"], .construction');
                    buildingEls.forEach(function(b) {
                        details.buildings.push(b.textContent.trim().substring(0, 20));
                    });
                    
                    return JSON.stringify({success: true, details: details});
                }, 1500);
                
                return JSON.stringify({success: true, message: 'Scanning...'});
            } catch(e) {
                return JSON.stringify({success: false, error: e.message});
            }
        })();
        """
        
        webView?.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }
            
            if let jsonString = result as? String,
               let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let success = json["success"] as? Bool, success,
               let details = json["details"] as? [String: Any] {
                
                var updatedVillage = village
                updatedVillage.name = details["name"] as? String ?? village.name
                updatedVillage.population = details["population"] as? Int ?? village.population
                updatedVillage.wood = details["wood"] as? Int ?? village.wood
                updatedVillage.clay = details["clay"] as? Int ?? village.clay
                updatedVillage.iron = details["iron"] as? Int ?? village.iron
                updatedVillage.wheat = details["wheat"] as? Int ?? village.wheat
                updatedVillage.hasTroops = details["hasTroops"] as? Bool ?? false
                updatedVillage.troopCount = details["troopCount"] as? Int ?? 0
                updatedVillage.wallLevel = details["wallLevel"] as? Int ?? 0
                updatedVillage.lastScouted = Date()
                
                DispatchQueue.main.async {
                    completion(updatedVillage)
                }
            } else {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    // MARK: - Map Scanner (مسح الخريطة)
    
    func scanMapArea(centerX: Int, centerY: Int, radius: Int, completion: @escaping ([VillageInfo]) -> Void) {
        let js = """
        (function() {
            try {
                var villages = [];
                
                // Navigate to map view
                var mapLink = document.querySelector('a[href*="karte.php"], a[href*="map"]');
                if (mapLink) mapLink.click();
                
                setTimeout(function() {
                    // Get all visible villages on map
                    var mapTiles = document.querySelectorAll('.map_tile, [class*="tile"], .tile');
                    
                    mapTiles.forEach(function(tile, index) {
                        var x = tile.getAttribute('data-x') || tile.style.left || '0';
                        var y = tile.getAttribute('data-y') || tile.style.top || '0';
                        
                        var info = tile.querySelector('.tip, [title], [data-title]');
                        var title = info ? (info.getAttribute('title') || info.getAttribute('data-title') || '') : '';
                        
                        if (title.length > 0) {
                            villages.push({
                                id: 'map_' + index,
                                name: title.substring(0, 30),
                                x: parseInt(x) || 0,
                                y: parseInt(y) || 0,
                                population: 0,
                                wood: 0,
                                clay: 0,
                                iron: 0,
                                wheat: 0,
                                hasTroops: false,
                                troopCount: 0,
                                wallLevel: 0
                            });
                        }
                    });
                    
                    return JSON.stringify({success: true, villages: villages, count: villages.length});
                }, 2000);
                
                return JSON.stringify({success: true, message: 'Scanning map...'});
            } catch(e) {
                return JSON.stringify({success: false, error: e.message});
            }
        })();
        """
        
        webView?.evaluateJavaScript(js) { result, error in
            if let jsonString = result as? String,
               let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let success = json["success"] as? Bool, success,
               let villagesArray = json["villages"] as? [[String: Any]] {
                
                let villages = villagesArray.compactMap { data -> VillageInfo? in
                    guard let id = data["id"] as? String else { return nil }
                    return VillageInfo(
                        id: id,
                        name: data["name"] as? String ?? "",
                        x: data["x"] as? Int ?? 0,
                        y: data["y"] as? Int ?? 0,
                        distance: 0,
                        population: data["population"] as? Int ?? 0,
                        wood: data["wood"] as? Int ?? 0,
                        clay: data["clay"] as? Int ?? 0,
                        iron: data["iron"] as? Int ?? 0,
                        wheat: data["wheat"] as? Int ?? 0,
                        lastScouted: Date()
                    )
                }
                
                DispatchQueue.main.async {
                    completion(villages)
                }
            } else {
                DispatchQueue.main.async {
                    completion([])
                }
            }
        }
    }
    
    // MARK: - Notifications
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    deinit {
        stopScouting()
        stopAutoAttack()
    }
}

// MARK: - Attack Record
struct AttackRecord: Identifiable {
    let id = UUID()
    let targetVillage: String
    let troopsSent: Int
    let timestamp: Date
    let estimatedLoot: Int
    var result: AttackResult
    var actualLoot: Int = 0
    
    enum AttackResult {
        case pending
        case success
        case failed
        case returned
    }
}
