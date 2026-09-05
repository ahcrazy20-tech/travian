import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: WebViewModel
    @Binding var isPresented: Bool
    @State private var customJS: String = ""
    @State private var showJSConsole = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("⚙️ الإعدادات")
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
                
                // Navigation buttons
                HStack(spacing: 12) {
                    NavButton(icon: "arrow.left", title: "رجوع") {
                        viewModel.goBack()
                    }
                    
                    NavButton(icon: "arrow.right", title: "تقدم") {
                        viewModel.goForward()
                    }
                    
                    NavButton(icon: "house.fill", title: "الرئيسية") {
                        viewModel.loadGame()
                    }
                    
                    NavButton(icon: "arrow.clockwise", title: "تحديث") {
                        viewModel.refresh()
                    }
                }
                .padding(.horizontal)
                
                // Current URL display
                VStack(alignment: .leading, spacing: 4) {
                    Text("الرابط الحالي:")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(viewModel.currentURL.isEmpty ? "جاري التحميل..." : viewModel.currentURL)
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                .padding(.horizontal)
                
                // JavaScript Console
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("💻 كونسول JavaScript")
                            .font(.subheadline)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button(action: { showJSConsole.toggle() }) {
                            Image(systemName: showJSConsole ? "chevron.up" : "chevron.down")
                                .foregroundColor(.gray)
                        }
                    }
                    
                    if showJSConsole {
                        TextEditor(text: $customJS)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.green)
                            .frame(height: 100)
                            .background(Color.black)
                            .cornerRadius(8)
                        
                        Button(action: {
                            viewModel.executeCustomJS(customJS)
                        }) {
                            Text("▶️ تنفيذ")
                                .font(.caption)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.green.opacity(0.8))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
                
                // Info section
                VStack(spacing: 8) {
                    Text("ℹ️ معلومات")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    
                    InfoRow(title: "اللعبة", value: "عصر التتار")
                    InfoRow(title: "الإصدار", value: "1.0.0")
                    InfoRow(title: "الجهاز", value: "iOS 16.4+")
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Tips
                VStack(alignment: .leading, spacing: 8) {
                    Text("💡 نصائح")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    
                    TipRow(text: "فعّل الأوتوماتك من الزرار اللي تحت")
                    TipRow(text: "التنبيهات هتشتغل حتى لو التطبيق متقفل")
                    TipRow(text: "استخدم كونسول JS لأوامر متقدمة")
                    TipRow(text: " والأوتوماتك بيفضل شغال في الخلفية 🎵 — ولو التطبيق اتقفل خالص، هيفتكر إعداداتك ويرجع شغّال لوحده لما تفتحه")
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(12)
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

struct NavButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.body)
                Text(title)
                    .font(.caption2)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.3))
            .cornerRadius(8)
        }
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(.white)
        }
    }
}

struct TipRow: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.yellow)
            Text(text)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}
