import SwiftUI

struct AutomationPanelView: View {
    @ObservedObject var viewModel: WebViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    HStack {
                        Text("🤖 مساعد الأوتوماتك")
                            .font(.headline)
                            .foregroundColor(.white)

                        Spacer()

                        Button(action: { isPresented = false }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)

                    Divider()
                        .background(Color.gray.opacity(0.3))

                    // Main automation toggle
                    HStack {
                        Image(systemName: viewModel.isAutomationEnabled ? "bolt.fill" : "bolt")
                            .foregroundColor(viewModel.isAutomationEnabled ? .green : .gray)
                            .font(.title2)

                        VStack(alignment: .leading) {
                            Text("تشغيل الأوتوماتك")
                                .font(.body)
                                .foregroundColor(.white)
                            Text(viewModel.isAutomationEnabled ? "شغّال ✅" : "موقف ❌")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { viewModel.isAutomationEnabled },
                            set: { _ in viewModel.toggleAutomation() }
                        ))
                        .utatarTint(.green)
                    }
                    .padding(.horizontal)

                    Divider()
                        .background(Color.gray.opacity(0.3))

                    // Automation options
                    VStack(spacing: 12) {
                        AutomationToggleRow(
                            icon: "leaf.fill",
                            title: "جمع الموارد تلقائي",
                            subtitle: "يلقط الموارد والبونص أوتوماتك",
                            isOn: $viewModel.autoCollectResources
                        )

                        AutomationToggleRow(
                            icon: "building.2.fill",
                            title: "بناء تلقائي",
                            subtitle: "يبني المباني الجديدة أوتوماتك",
                            isOn: $viewModel.autoBuildQueue
                        )

                        AutomationToggleRow(
                            icon: "person.3.fill",
                            title: "تدريب جنود تلقائي",
                            subtitle: "يدرب جنود لما يقدر",
                            isOn: $viewModel.autoTrainTroops
                        )

                        AutomationToggleRow(
                            icon: "exclamationmark.triangle.fill",
                            title: "تنبيهات الهجمات",
                            subtitle: "بيلقط أي هجوم جاي",
                            isOn: $viewModel.attackAlerts,
                            color: .red
                        )

                        AutomationToggleRow(
                            icon: "archivebox.fill",
                            title: "تنبيه مخزن مليان",
                            subtitle: "بيلقطك لما المخزن يملي",
                            isOn: $viewModel.resourceFullAlerts,
                            color: .orange
                        )

                        AutomationToggleRow(
                            icon: "checkmark.seal.fill",
                            title: "تنبيه بناء خلص",
                            subtitle: "بيلقطك لما مبنى يخلص",
                            isOn: $viewModel.buildCompleteAlerts,
                            color: .blue
                        )
                    }
                    .padding(.horizontal)

                    // ===== الموارد الحقيقية =====
                    VStack(spacing: 16) {
                        RealResourcesCard(viewModel: viewModel)

                        // ===== الجنود في القرية =====
                        HomeTroopsCard(viewModel: viewModel)

                        // ===== التدريب (صفحة الثكنات) =====
                        TrainingCard(viewModel: viewModel)

                        // ===== القرى المكتشفة + التجسس =====
                        VillagesCard(viewModel: viewModel)

                        // ===== تقارير التجسس =====
                        SpyReportsCard(viewModel: viewModel)

                        // Quick actions
                        HStack(spacing: 12) {
                            QuickActionButton(title: "🔄 تحديث", color: .blue) {
                                viewModel.refresh()
                            }

                            QuickActionButton(title: "⚡ فعّال كله", color: .green) {
                                viewModel.autoCollectResources = true
                                viewModel.autoBuildQueue = true
                                viewModel.autoTrainTroops = true
                                viewModel.attackAlerts = true
                                viewModel.resourceFullAlerts = true
                                viewModel.buildCompleteAlerts = true
                                if !viewModel.isAutomationEnabled {
                                    viewModel.toggleAutomation()
                                }
                            }

                            QuickActionButton(title: "⏹️ وقّف كله", color: .red) {
                                viewModel.autoCollectResources = false
                                viewModel.autoBuildQueue = false
                                viewModel.autoTrainTroops = false
                                if viewModel.isAutomationEnabled {
                                    viewModel.toggleAutomation()
                                }
                            }
                        }
                        .padding(.horizontal)

                        if !viewModel.gameLog.isEmpty {
                            Text(viewModel.gameLog)
                                .font(.caption2)
                                .foregroundColor(.yellow)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                                .padding(.horizontal)
                        }

                        Text("الصفحة الحالية: \(viewModel.pageKind.isEmpty ? "-" : viewModel.pageKind)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .padding(.bottom, 16)
                    }
                }
            }
            .frame(maxHeight: 620)
            .background(Color.black.opacity(0.95))
            .cornerRadius(20)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - كارت الموارد الحقيقية

struct RealResourcesCard: View {
    @ObservedObject var viewModel: WebViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("📊 الموارد الحقيقية")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                Button(action: { viewModel.refreshGameData() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            if let res = viewModel.gameResources {
                ResBar(label: "🪵", value: res.wood, cap: res.woodCap, color: .orange)
                ResBar(label: "🧱", value: res.clay, cap: res.clayCap, color: .brown)
                ResBar(label: "⚙️", value: res.iron, cap: res.ironCap, color: .gray)
                ResBar(label: "🌾", value: res.crop, cap: res.cropCap, color: .green)
                if res.cropProd != 0 {
                    Text("إنتاج القمح: \(res.cropProd)/ساعة")
                        .font(.caption2)
                        .foregroundColor(res.cropProd < 0 ? .red : .green)
                }
            } else {
                Text("افتح أي صفحة في اللعبة عشان أقرا الموارد")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct ResBar: View {
    let label: String
    let value: Int
    let cap: Int
    let color: Color

    private var amountText: String {
        if cap > 0 {
            return "\(label) \(value) / \(cap)"
        }
        return "\(label) \(value)"
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(amountText)
                    .font(.caption2)
                    .foregroundColor(.white)
                Spacer()
                if cap > 0 {
                    Text("\(Int(Double(value) / Double(max(1, cap)) * 100))%")
                        .font(.caption2)
                        .foregroundColor(value >= cap ? .red : .gray)
                }
            }
            if cap > 0 {
                ProgressView(value: min(1.0, Double(value) / Double(max(1, cap))))
                    .utatarTint(color)
            }
        }
    }
}

// MARK: - كارت الجنود في القرية

struct HomeTroopsCard: View {
    @ObservedObject var viewModel: WebViewModel

    private var totalTroops: Int {
        viewModel.homeTroops.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("⚔️ الجنود في قريتك")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                Text("المجموع: \(totalTroops)")
                    .font(.caption2)
                    .foregroundColor(.white)
            }

            if viewModel.homeTroops.isEmpty {
                Text("افتح نقطة التجمع (القرية ← نقطة التجمع) عشان أشوف الجنود")
                    .font(.caption2)
                    .foregroundColor(.gray)
            } else {
                ForEach(viewModel.homeTroops.filter { $0.count > 0 }) { unit in
                    HStack {
                        Text(GameEngine.arabicUnitName(unit.id))
                            .font(.caption)
                            .foregroundColor(.white)
                        if !unit.name.isEmpty && unit.name != GameEngine.arabicUnitName(unit.id) {
                            Text(unit.name)
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Text("×\(unit.count)")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - كارت التدريب

struct TrainingCard: View {
    @ObservedObject var viewModel: WebViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("🏗️ التدريب (افتح الثكنات)")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                if !viewModel.trainableUnits.isEmpty {
                    Button(action: { trainAllMax() }) {
                        Text("درّب الأقصى")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.8))
                            .cornerRadius(6)
                    }
                }
            }

            if viewModel.trainableUnits.isEmpty {
                Text("لما تفتح الثكنات (build.php?id=19) هعرض أنواع الجنود والحد الأقصى والتكلفة")
                    .font(.caption2)
                    .foregroundColor(.gray)
            } else {
                ForEach(viewModel.trainableUnits) { unit in
                    TrainRow(viewModel: viewModel, unit: unit)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func trainAllMax() {
        let units = viewModel.trainableUnits
        viewModel.engine.trainAllMax(units) { msg in
            DispatchQueue.main.async {
                viewModel.gameLog = msg
            }
        }
    }
}

struct TrainRow: View {
    @ObservedObject var viewModel: WebViewModel
    let unit: TrainableUnit
    @State private var countText: String = ""

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(unit.name.isEmpty ? GameEngine.arabicUnitName(Int(unit.id.replacingOccurrences(of: "t", with: "")) ?? 0) : unit.name)
                    .font(.caption)
                    .foregroundColor(.white)
                Spacer()
                if unit.max > 0 {
                    Text("الحد: \(unit.max)")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }

            let affordableNow = unit.affordable(with: viewModel.gameResources ?? GameResources())
            HStack(spacing: 8) {
                TextField("العدد", text: $countText)
                    .keyboardType(.numberPad)
                    .font(.caption)
                    .foregroundColor(.white)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)

                if affordableNow > 0 {
                    Button(action: { countText = "\(affordableNow)" }) {
                        Text("الأقصى الممكن (\(affordableNow))")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                }

                Spacer()

                Button(action: { trainNow() }) {
                    Text("درّب")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.85))
                        .cornerRadius(6)
                }
            }

            if unit.costWood > 0 {
                Text("التكلفة للواحد: 🪵\(unit.costWood) 🧱\(unit.costClay) ⚙️\(unit.costIron) 🌾\(unit.costCrop)")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 4)
    }

    private func trainNow() {
        let count = Int(countText) ?? 0
        guard count > 0 else {
            viewModel.gameLog = "اكتب العدد الأول"
            return
        }
        viewModel.engine.trainUnit(unit.id, count: count) { msg in
            DispatchQueue.main.async {
                viewModel.gameLog = msg
            }
        }
    }
}

// MARK: - كارت القرى + التجسس

struct VillagesCard: View {
    @ObservedObject var viewModel: WebViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("🗺️ القرى على الخريطة")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                if viewModel.isScanningMap {
                    ProgressView().utatarTint(.white)
                } else {
                    Button(action: { viewModel.openMap() }) {
                        Text("افتح الخريطة")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.8))
                            .cornerRadius(6)
                    }
                }
            }

            if viewModel.mapVillages.isEmpty {
                Text("افتح الخريطة (karte.php) وأنا أمسح القرى لوحدي")
                    .font(.caption2)
                    .foregroundColor(.gray)
            } else {
                ForEach(viewModel.mapVillages.prefix(12)) { village in
                    VillageCardRow(viewModel: viewModel, village: village)
                }
                if viewModel.mapVillages.count > 12 {
                    Text("+ \(viewModel.mapVillages.count - 12) قرية أخرى")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct VillageCardRow: View {
    @ObservedObject var viewModel: WebViewModel
    let village: MapVillage

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(village.name.isEmpty ? "قرية (\(village.x)|\(village.y))" : village.name)
                    .font(.caption)
                    .foregroundColor(.white)
                HStack(spacing: 8) {
                    Text("(\(village.x)|\(village.y))")
                        .foregroundColor(.blue)
                    if !village.player.isEmpty {
                        Text("👤 \(village.player)")
                    }
                    if village.population > 0 {
                        Text("👥 \(village.population)")
                    }
                }
                .font(.caption2)
                .foregroundColor(.gray)
            }

            Spacer()

            Button(action: { viewModel.startSpy(village) }) {
                Text("🕵️ جسّس")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.purple.opacity(0.85))
                    .cornerRadius(6)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - كارت تقارير التجسس

struct SpyReportsCard: View {
    @ObservedObject var viewModel: WebViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("📜 تقارير التجسس")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                Button(action: { viewModel.refreshGameData() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            if viewModel.spyReports.isEmpty {
                Text("افتح صفحة التقارير (berichte.php) بعد ما الجواسيس يرجعوا")
                    .font(.caption2)
                    .foregroundColor(.gray)
            } else {
                ForEach(viewModel.spyReports) { report in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(report.subject)
                            .font(.caption2)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text("🪵\(report.wood) 🧱\(report.clay) ⚙️\(report.iron) 🌾\(report.crop)\(report.wallLevel >= 0 ? " — 🧱 جدار \(report.wallLevel)" : "")")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                        if !report.troopsText.isEmpty {
                            Text("⚔️ \(report.troopsText)")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Color.gray.opacity(0.18))
                    .cornerRadius(6)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - Rows المساعدة

struct AutomationToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var color: Color = .green

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.body)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .utatarTint(color)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

struct QuickActionButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(color.opacity(0.8))
                .cornerRadius(8)
        }
    }
}
