import SwiftUI

struct SpyAttackPanelView: View {
    @ObservedObject var bot: SpyAttackBot
    @Binding var isPresented: Bool
    @State private var selectedTab = 0
    @State private var showSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("🕵️ بوت التجسس والهجوم")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gear")
                            .foregroundColor(.gray)
                    }
                    
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                
                // Tab bar
                HStack(spacing: 0) {
                    TabButton(title: "🎯 أهداف", isSelected: selectedTab == 0) {
                        selectedTab = 0
                    }
                    TabButton(title: "🏘️ قرى", isSelected: selectedTab == 1) {
                        selectedTab = 1
                    }
                    TabButton(title: "📜 سجل", isSelected: selectedTab == 2) {
                        selectedTab = 2
                    }
                }
                .padding(.horizontal)
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                // Content based on selected tab
                ScrollView {
                    VStack(spacing: 12) {
                        switch selectedTab {
                        case 0:
                            targetsTab
                        case 1:
                            villagesTab
                        case 2:
                            historyTab
                        default:
                            EmptyView()
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 400)
                
                // Control buttons
                HStack(spacing: 12) {
                    // Scout button
                    Button(action: {
                        if bot.isScouting {
                            bot.stopScouting()
                        } else {
                            bot.startScouting()
                        }
                    }) {
                        HStack {
                            Image(systemName: bot.isScouting ? "eye.slash.fill" : "eye.fill")
                            Text(bot.isScouting ? "وقف تجسس" : "ابدأ تجسس")
                        }
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(bot.isScouting ? Color.orange : Color.blue)
                        .cornerRadius(10)
                    }
                    
                    // Attack button
                    Button(action: {
                        if bot.isAttacking {
                            bot.stopAutoAttack()
                        } else {
                            bot.startAutoAttack()
                        }
                    }) {
                        HStack {
                            Image(systemName: bot.isAttacking ? "stop.fill" : "bolt.fill")
                            Text(bot.isAttacking ? "وقف هجوم" : "هجوم تلقائي")
                        }
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(bot.isAttacking ? Color.red : Color.green)
                        .cornerRadius(10)
                    }
                }
                .padding()
            }
            .background(Color.black.opacity(0.95))
            .cornerRadius(20)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showSettings) {
            FarmingSettingsView(bot: bot, isPresented: $showSettings)
        }
    }
    
    // MARK: - Targets Tab
    
    var targetsTab: some View {
        VStack(spacing: 12) {
            // Stats
            HStack(spacing: 16) {
                StatBadge(title: "🎯 أهداف", value: "\(bot.attackTargets.count)", color: .red)
                StatBadge(title: "💰 أغنى هدف", value: "\(bot.attackTargets.first?.estimatedLoot ?? 0)", color: .yellow)
                StatBadge(title: "⚔️ هجمات/ساعة", value: "\(bot.farmingSettings.maxAttacksPerHour)", color: .orange)
            }
            
            if bot.attackTargets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text("مفيش أهداف دلوقتي")
                        .foregroundColor(.gray)
                    Text("فعّل التجسس الأول عشان تكتشف القرى")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.7))
                }
                .padding(.vertical, 30)
            } else {
                ForEach(bot.attackTargets.prefix(10)) { target in
                    TargetRow(target: target) {
                        // Manual attack
                        bot.sendAttackManually(to: target)
                    }
                }
            }
        }
    }
    
    // MARK: - Villages Tab
    
    var villagesTab: some View {
        VStack(spacing: 12) {
            // Stats
            HStack(spacing: 16) {
                StatBadge(title: "🏘️ قرى", value: "\(bot.discoveredVillages.count)", color: .blue)
                StatBadge(title: "💰 غنية", value: "\(bot.discoveredVillages.filter { $0.isRich }.count)", color: .green)
                StatBadge(title: "⚔️ مسلحة", value: "\(bot.discoveredVillages.filter { $0.hasTroops }.count)", color: .red)
            }
            
            if bot.discoveredVillages.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "map")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text("مفيش قرى مكتشفة")
                        .foregroundColor(.gray)
                    Text("ابدأ التجسس عشان تكتشف القرى حواليك")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.7))
                }
                .padding(.vertical, 30)
            } else {
                ForEach(bot.discoveredVillages.prefix(20)) { village in
                    VillageRow(village: village) {
                        // Scan village details
                        bot.scanVillageDetails(village) { updated in
                            if let updated = updated {
                                // Update village in list
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - History Tab
    
    var historyTab: some View {
        VStack(spacing: 12) {
            // Stats
            HStack(spacing: 16) {
                StatBadge(title: "📜 هجمات", value: "\(bot.attackHistory.count)", color: .purple)
                StatBadge(title: "✅ ناجحة", value: "\(bot.attackHistory.filter { $0.result == .success }.count)", color: .green)
                StatBadge(title: "💰 غنيمة", value: "\(bot.attackHistory.reduce(0) { $0 + $1.actualLoot })", color: .yellow)
            }
            
            if bot.attackHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text("مفيش هجمات لسه")
                        .foregroundColor(.gray)
                }
                .padding(.vertical, 30)
            } else {
                ForEach(bot.attackHistory.reversed().prefix(20)) { record in
                    AttackRecordRow(record: record)
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(isSelected ? .white : .gray)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(isSelected ? Color.blue.opacity(0.5) : Color.clear)
                .cornerRadius(8)
        }
    }
}

struct StatBadge: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.gray)
            Text(value)
                .font(.headline)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
    }
}

struct TargetRow: View {
    let target: AttackTarget
    let onAttack: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(target.village.name)
                    .font(.subheadline)
                    .foregroundColor(.white)
                
                HStack(spacing: 8) {
                    Text("🪵\(target.village.wood)")
                    Text("🧱\(target.village.clay)")
                    Text("⚙️\(target.village.iron)")
                    Text("🌾\(target.village.wheat)")
                }
                .font(.caption2)
                .foregroundColor(.gray)
                
                HStack(spacing: 8) {
                    Text(target.riskLevel.rawValue)
                    Text("👥 \(target.recommendedTroops) جندي")
                }
                .font(.caption)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("💰 \(target.estimatedLoot)")
                    .font(.headline)
                    .foregroundColor(.yellow)
                
                Button(action: onAttack) {
                    Text("⚔️ هاجم")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .cornerRadius(6)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(10)
    }
}

struct VillageRow: View {
    let village: VillageInfo
    let onScan: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(village.name)
                    .font(.subheadline)
                    .foregroundColor(.white)
                
                HStack(spacing: 8) {
                    Text("👥 \(village.population)")
                    if village.hasTroops {
                        Text("⚔️ \(village.troopCount)")
                            .foregroundColor(.red)
                    }
                    if village.wallLevel > 0 {
                        Text("🧱 جدار \(village.wallLevel)")
                    }
                }
                .font(.caption)
                .foregroundColor(.gray)
                
                HStack(spacing: 6) {
                    Text("🪵\(village.wood)")
                    Text("🧱\(village.clay)")
                    Text("⚙️\(village.iron)")
                    Text("🌾\(village.wheat)")
                }
                .font(.caption2)
                .foregroundColor(.gray)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if village.isRich {
                    Text("💰 غنية")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                
                Button(action: onScan) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.blue)
                        .cornerRadius(6)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(10)
    }
}

struct AttackRecordRow: View {
    let record: AttackRecord
    
    var resultIcon: String {
        switch record.result {
        case .pending: return "⏳"
        case .success: return "✅"
        case .failed: return "❌"
        case .returned: return "↩️"
        }
    }
    
    var body: some View {
        HStack {
            Text(resultIcon)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(record.targetVillage)
                    .font(.subheadline)
                    .foregroundColor(.white)
                
                Text("\(record.troopsSent) جندي • \(record.timestamp, style: .relative)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("💰 \(record.actualLoot > 0 ? record.actualLoot : record.estimatedLoot)")
                    .font(.subheadline)
                    .foregroundColor(.yellow)
                
                if record.actualLoot > 0 {
                    Text("غنيمة فعلية")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(10)
    }
}

// MARK: - Farming Settings View

struct FarmingSettingsView: View {
    @ObservedObject var bot: SpyAttackBot
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("⚙️ إعدادات التجسس")) {
                    Toggle("تجسس تلقائي", isOn: $bot.farmingSettings.autoScoutEnabled)
                    Toggle("تجاهل اللاعبين النشطين", isOn: $bot.farmingSettings.avoidActivePlayers)
                    Toggle("تجاهل الجدران العالية", isOn: $bot.farmingSettings.avoidHighWall)
                    
                    HStack {
                        Text("أقصى مستوى جدار")
                        Spacer()
                        Picker("", selection: $bot.farmingSettings.maxWallLevel) {
                            ForEach(0..<21) { level in
                                Text("\(level)").tag(level)
                            }
                        }
                    }
                    
                    HStack {
                        Text("فترة التجسس")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { Int(bot.farmingSettings.scoutInterval / 60) },
                            set: { bot.farmingSettings.scoutInterval = TimeInterval($0 * 60) }
                        )) {
                            Text("دقيقة").tag(1)
                            Text("3 دقائق").tag(3)
                            Text("5 دقائق").tag(5)
                            Text("10 دقائق").tag(10)
                            Text("30 دقيقة").tag(30)
                        }
                    }
                }
                
                Section(header: Text("⚔️ إعدادات الهجوم")) {
                    Toggle("هجوم تلقائي", isOn: $bot.farmingSettings.autoAttackEnabled)
                    Toggle("استخدم جواسيس فقط", isOn: $bot.farmingSettings.useOnlyScouts)
                    Toggle("حفظ التقارير", isOn: $bot.farmingSettings.saveReports)
                    
                    HStack {
                        Text("أقل موارد للهجوم")
                        Spacer()
                        Picker("", selection: $bot.farmingSettings.minResourcesToAttack) {
                            Text("100").tag(100)
                            Text("500").tag(500)
                            Text("1000").tag(1000)
                            Text("2000").tag(2000)
                            Text("5000").tag(5000)
                        }
                    }
                    
                    HStack {
                        Text("أقصى مسافة")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { Int(bot.farmingSettings.maxDistance) },
                            set: { bot.farmingSettings.maxDistance = Double($0) }
                        )) {
                            Text("5").tag(5)
                            Text("10").tag(10)
                            Text("20").tag(20)
                            Text("50").tag(50)
                            Text("100").tag(100)
                        }
                    }
                    
                    HStack {
                        Text("هجمات/ساعة")
                        Spacer()
                        Picker("", selection: $bot.farmingSettings.maxAttacksPerHour) {
                            Text("5").tag(5)
                            Text("10").tag(10)
                            Text("20").tag(20)
                            Text("50").tag(50)
                        }
                    }
                    
                    HStack {
                        Text("جنود للهجوم")
                        VStack {
                            Stepper("أقل: \(bot.farmingSettings.minTroopsToSend)", value: $bot.farmingSettings.minTroopsToSend, in: 1...50)
                            Stepper("أقصى: \(bot.farmingSettings.maxTroopsToSend)", value: $bot.farmingSettings.maxTroopsToSend, in: 1...100)
                        }
                    }
                }
                
                Section(header: Text("⏱️ فترات الهجوم")) {
                    HStack {
                        Text("فترة الهجوم")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { Int(bot.farmingSettings.attackInterval / 60) },
                            set: { bot.farmingSettings.attackInterval = TimeInterval($0 * 60) }
                        )) {
                            Text("دقيقة").tag(1)
                            Text("5 دقائق").tag(5)
                            Text("10 دقائق").tag(10)
                            Text("30 دقيقة").tag(30)
                            Text("ساعة").tag(60)
                        }
                    }
                }
            }
            .navigationTitle("⚙️ إعدادات البوت")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("تم") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

// MARK: - Extension for manual attack

extension SpyAttackBot {
    func sendAttackManually(to target: AttackTarget) {
        sendAttack(to: target)
    }
}
