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
    
    // MARK: - Resource Filters (فلاتر الموارد)
    var minWoodToAttack: Int = 200
    var minClayToAttack: Int = 200
    var minIronToAttack: Int = 200
    var minWheatToAttack: Int = 100
    var minTotalResources: Int = 500
    var searchForWood: Bool = true
    var searchForClay: Bool = true
    var searchForIron: Bool = true
    var searchForWheat: Bool = true
    
    // MARK: - Troop Settings (إعدادات الجنود)
    var usePercentageOfTroops: Bool = true  // Use percentage instead of fixed number
    var troopPercentage: Int = 50  // Use 50% of available troops
    var fixedTroopCount: Int = 20  // Fixed number if not using percentage
    var minTroopsToSend: Int = 5
    var maxTroopsToSend: Int = 100
    var keepTroopsInVillage: Int = 10  // Always keep this many troops at home
    var preferScouts: Bool = false  // Send scouts first
    var scoutCount: Int = 3  // Number of scouts to send
    
    // MARK: - Distance & Risk (المسافة والمخاطرة)
    var maxDistance: Double = 20.0
    var avoidActivePlayers: Bool = true
    var avoidHighWall: Bool = true
    var maxWallLevel: Int = 5
    var avoidTribes: [String] = []  // Tribes to avoid
    
    // MARK: - Timing (التوقيت)
    var scoutInterval: TimeInterval = 300  // 5 minutes
    var attackInterval: TimeInterval = 600  // 10 minutes
    var maxAttacksPerHour: Int = 10
    var randomDelay: Bool = true  // Add random delay between attacks
    var minDelay: Int = 30  // Minimum delay in seconds
    var maxDelay: Int = 120  // Maximum delay in seconds
    
    // MARK: - Auto Retreat (الهروب التلقائي)
    var autoRetreatOnAttack: Bool = true  // هروب تلقائي لما يهاجموني
    var retreatToOasis: Bool = false  // هروب لواحة
    var retreatTargetX: Int = 0  // إحداثيات الهروب
    var retreatTargetY: Int = 0
    var retreatAllTroops: Bool = true  // هروب كل الجنود
    var keepDefenders: Bool = false  // Keep some troops to defend
    var defenderCount: Int = 5  // Number of troops to keep
    
    // MARK: - Advanced (متقدم)
    var useOnlyScouts: Bool = false
    var saveReports: Bool = true
    var autoAcceptFarms: Bool = true  // Auto accept farm lists
    var autoSendFarms: Bool = false  // Auto send farm lists
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
        // Check resource filters
        guard passesResourceFilter(village) else { return nil }
        
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
        
        // Calculate recommended troops (will be adjusted based on available troops)
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
        
        // Get available troops first
        getAvailableTroops { [weak self] availableTroops in
            guard let self = self else { return }
            
            let troopCount = self.calculateTroopCount(availableTroops: availableTroops)
            
            guard troopCount > 0 else {
                print("⚠️ No troops available for attack")
                return
            }
            
            // Add random delay if enabled
            if self.farmingSettings.randomDelay {
                let delay = Int.random(in: self.farmingSettings.minDelay...self.farmingSettings.maxDelay)
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(delay)) {
                    self.sendAttack(to: target, troopCount: troopCount)
                }
            } else {
                self.sendAttack(to: target, troopCount: troopCount)
            }
        }
    }
    
    private func sendAttack(to target: AttackTarget, troopCount: Int? = nil) {
        let troopsToSend = troopCount ?? target.recommendedTroops
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
                    
                    // Set troop count - try multiple selectors
                    var troopInputs = document.querySelectorAll('input[name*="t"], input[class*="troop_input"], .troop_input input');
                    troopInputs.forEach(function(input, index) {
                        if (index === 0) {
                            // Set first troop type to the calculated amount
                            input.value = '\(troopsToSend)';
                        } else {
                            // Set other troop types to 0
                            input.value = '0';
                        }
                    });
                    
                    // If no troop inputs found, try generic selector
                    if (troopInputs.length === 0) {
                        var troopInput = document.querySelector('input[name*="troop"], input[name*="t1"]');
                        if (troopInput) {
                            troopInput.value = '\(troopsToSend)';
                        }
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
                            return JSON.stringify({success: true, message: 'Attack sent to \(target.village.name) with \(troopsToSend) troops'});
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
                        troopsSent: troopsToSend,
                        timestamp: Date(),
                        estimatedLoot: target.estimatedLoot,
                        result: .pending
                    )
                    self.attackHistory.append(record)
                    
                    // Send notification
                    self.sendNotification(
                        title: "⚔️ هجوم تم إرساله!",
                        body: "هجوم على \(target.village.name) بـ \(troopsToSend) جندي"
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
    
    // MARK: - Auto Retreat (الهروب التلقائي)
    
    func checkForIncomingAttacks() {
        let js = """
        (function() {
            try {
                var attacks = [];
                
                // Check for incoming attacks
                var attackRows = document.querySelectorAll('.attack_row, [class*="incoming"], tr[class*="attack"], .inAttack');
                
                attackRows.forEach(function(row, index) {
                    var timeEl = row.querySelector('.timer, [class*="time"], .duration');
                    var troopsEl = row.querySelector('.troop_count, [class*="troop"]');
                    var fromEl = row.querySelector('.from, [class*="source"]');
                    
                    var time = timeEl ? timeEl.textContent.trim() : '';
                    var troops = troopsEl ? parseInt(troopsEl.textContent) || 0 : 0;
                    var from = fromEl ? fromEl.textContent.trim() : '';
                    
                    // Parse time to seconds
                    var timeParts = time.split(':');
                    var seconds = 0;
                    if (timeParts.length >= 3) {
                        seconds = parseInt(timeParts[0]) * 3600 + parseInt(timeParts[1]) * 60 + parseInt(timeParts[2]);
                    } else if (timeParts.length >= 2) {
                        seconds = parseInt(timeParts[0]) * 60 + parseInt(timeParts[1]);
                    }
                    
                    attacks.push({
                        index: index,
                        time: time,
                        seconds: seconds,
                        troops: troops,
                        from: from,
                        isScout: troops <= 3
                    });
                });
                
                // Also check for attack warning banner
                var warning = document.querySelector('.attack_warning, [class*="attackWarning"], #attack_alert');
                var hasWarning = warning !== null;
                
                return JSON.stringify({
                    success: true,
                    attacks: attacks,
                    count: attacks.length,
                    hasWarning: hasWarning,
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
               let attacks = json["attacks"] as? [[String: Any]],
               let count = json["count"] as? Int, count > 0 {
                
                DispatchQueue.main.async {
                    // Send notification about incoming attacks
                    self.sendNotification(
                        title: "⚠️ هجوم قادم!",
                        body: "في \(count) هجوم جايين عليك!"
                    )
                    
                    // Auto retreat if enabled
                    if self.farmingSettings.autoRetreatOnAttack {
                        self.executeRetreat()
                    }
                }
            }
        }
    }
    
    func executeRetreat() {
        let keepDefenders = farmingSettings.keepDefenders
        let defenderCount = farmingSettings.defenderCount
        
        let js = """
        (function() {
            try {
                // Navigate to rally point
                var rallyLink = document.querySelector('a[href*="build.php?id=39"], a[href*="rally"], [class*="rally_point"]');
                if (rallyLink) {
                    rallyLink.click();
                }
                
                setTimeout(function() {
                    // Get all available troops
                    var troopInputs = document.querySelectorAll('input[name*="t"], input[class*="troop_input"], .troop_input input');
                    var totalTroops = 0;
                    var troopValues = [];
                    
                    troopInputs.forEach(function(input) {
                        var max = input.getAttribute('max') || input.parentElement.querySelector('.max') || '0';
                        var maxVal = parseInt(max) || parseInt(input.max) || 0;
                        troopValues.push({input: input, max: maxVal});
                        totalTroops += maxVal;
                    });
                    
                    // Calculate troops to send
                    var troopsToSend = totalTroops;
                    if (\(keepDefenders ? "true" : "false")) {
                        troopsToSend = Math.max(0, totalTroops - \(defenderCount));
                    }
                    
                    if (troopsToSend <= 0) {
                        return JSON.stringify({success: false, message: 'No troops to retreat'});
                    }
                    
                    // Set troops to send (all or minus defenders)
                    troopValues.forEach(function(tv) {
                        if (\(keepDefenders ? "true" : "false")) {
                            // Keep some defenders
                            var toSend = Math.max(0, tv.max - Math.ceil(\(defenderCount) / troopValues.length));
                            tv.input.value = toSend.toString();
                        } else {
                            // Send all
                            tv.input.value = tv.max.toString();
                        }
                    });
                    
                    // Set target coordinates (retreat target or oasis)
                    var xInput = document.querySelector('input[name="x"], input[name="coord_x"], #xCoordInput');
                    var yInput = document.querySelector('input[name="y"], input[name="coord_y"], #yCoordInput');
                    
                    var targetX = \(farmingSettings.retreatTargetX);
                    var targetY = \(farmingSettings.retreatTargetY);
                    
                    if (targetX !== 0 || targetY !== 0) {
                        // Use custom retreat target
                        if (xInput) xInput.value = targetX.toString();
                        if (yInput) yInput.value = targetY.toString();
                    } else {
                        // Find nearest oasis to retreat to
                        var oasisLinks = document.querySelectorAll('a[href*="karte.php"][class*="oasis"], .oasis_link');
                        if (oasisLinks.length > 0) {
                            oasisLinks[0].click();
                        }
                    }
                    
                    // Select reinforce/transfer mode (not attack)
                    var reinforceOption = document.querySelector('input[value="2"], input[name="type"][value="2"], .reinforce_option, [class*="support"]');
                    if (reinforceOption) {
                        reinforceOption.click();
                    }
                    
                    // Click send
                    setTimeout(function() {
                        var sendBtn = document.querySelector('#btn_send, .send_button, input[type="submit"], button[type="submit"]');
                        if (sendBtn) {
                            sendBtn.click();
                            return JSON.stringify({success: true, message: 'Retreating ' + troopsToSend + ' troops'});
                        }
                        return JSON.stringify({success: false, message: 'Send button not found'});
                    }, 500);
                    
                }, 1000);
                
                return JSON.stringify({success: true, message: 'Preparing retreat...'});
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
                
                let message = json["message"] as? String ?? "Retreat executed"
                
                DispatchQueue.main.async {
                    self.sendNotification(
                        title: "🏃 هروب تلقائي!",
                        body: message
                    )
                }
            }
        }
    }
    
    // MARK: - Get Available Troops (الحصول على الجنود المتاحين)
    
    func getAvailableTroops(completion: @escaping (Int) -> Void) {
        let js = """
        (function() {
            try {
                var totalTroops = 0;
                
                // Method 1: Check rally point
                var troopElements = document.querySelectorAll('.troop_count, [class*="troop_count"], .unit_count');
                troopElements.forEach(function(el) {
                    var count = parseInt(el.textContent.replace(/[^0-9]/g, ''));
                    if (!isNaN(count)) totalTroops += count;
                });
                
                // Method 2: Check village overview
                var overviewTroops = document.querySelectorAll('.troops_list .count, [class*="troops"] .count');
                overviewTroops.forEach(function(el) {
                    var count = parseInt(el.textContent.replace(/[^0-9]/g, ''));
                    if (!isNaN(count)) totalTroops += count;
                });
                
                // Method 3: Check for troop inputs with max values
                var troopInputs = document.querySelectorAll('input[name*="t"], input[class*="troop"]');
                troopInputs.forEach(function(input) {
                    var max = parseInt(input.getAttribute('max') || input.max || '0');
                    if (!isNaN(max)) totalTroops += max;
                });
                
                return JSON.stringify({success: true, totalTroops: totalTroops});
            } catch(e) {
                return JSON.stringify({success: false, error: e.message, totalTroops: 0});
            }
        })();
        """
        
        webView?.evaluateJavaScript(js) { result, error in
            if let jsonString = result as? String,
               let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let totalTroops = json["totalTroops"] as? Int {
                completion(totalTroops)
            } else {
                completion(0)
            }
        }
    }
    
    // MARK: - Enhanced Attack with Percentage (هجوم بنسبة من الجنود)
    
    private func calculateTroopCount(availableTroops: Int) -> Int {
        if farmingSettings.usePercentageOfTroops {
            // Use percentage of available troops
            let percentageCount = availableTroops * farmingSettings.troopPercentage / 100
            let afterKeep = max(0, percentageCount - farmingSettings.keepTroopsInVillage)
            return min(farmingSettings.maxTroopsToSend, max(farmingSettings.minTroopsToSend, afterKeep))
        } else {
            // Use fixed number
            let afterKeep = max(0, farmingSettings.fixedTroopCount)
            return min(farmingSettings.maxTroopsToSend, max(farmingSettings.minTroopsToSend, afterKeep))
        }
    }
    
    // MARK: - Check Resource Filters (فحص فلاتر الموارد)
    
    private func passesResourceFilter(_ village: VillageInfo) -> Bool {
        // Check if village has minimum resources for each type
        if farmingSettings.searchForWood && village.wood < farmingSettings.minWoodToAttack {
            return false
        }
        if farmingSettings.searchForClay && village.clay < farmingSettings.minClayToAttack {
            return false
        }
        if farmingSettings.searchForIron && village.iron < farmingSettings.minIronToAttack {
            return false
        }
        if farmingSettings.searchForWheat && village.wheat < farmingSettings.minWheatToAttack {
            return false
        }
        
        // Check total resources
        if village.totalResources < farmingSettings.minTotalResources {
            return false
        }
        
        return true
    }
    
    deinit {
        stopScouting()
        stopAutoAttack()
    }
}

// MARK: - Extension for manual attack and monitoring

extension SpyAttackBot {
    func sendAttackManually(to target: AttackTarget) {
        // Get available troops first
        getAvailableTroops { [weak self] availableTroops in
            guard let self = self else { return }
            let troopCount = self.calculateTroopCount(availableTroops: availableTroops)
            self.sendAttack(to: target, troopCount: troopCount)
        }
    }
    
    func startAttackMonitoring() {
        // Monitor for incoming attacks every 30 seconds
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkForIncomingAttacks()
        }
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
