import SwiftUI

struct AutomationPanelView: View {
    @ObservedObject var viewModel: WebViewModel
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
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
                    .tint(.green)
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
                
                // Game stats
                VStack(spacing: 8) {
                    Text("📊 الموارد الحالية")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    HStack(spacing: 20) {
                        ResourceBadge(icon: "🪵", value: viewModel.woodAmount)
                        ResourceBadge(icon: "🧱", value: viewModel.clayAmount)
                        ResourceBadge(icon: "⚙️", value: viewModel.ironAmount)
                        ResourceBadge(icon: "🌾", value: viewModel.wheatAmount)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(12)
                .padding(.horizontal)
                
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
                .padding(.bottom, 16)
            }
            .background(Color.black.opacity(0.95))
            .cornerRadius(20)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }
}

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
                .tint(color)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

struct ResourceBadge: View {
    let icon: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(icon)
                .font(.title3)
            Text(value)
                .font(.caption2)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
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
