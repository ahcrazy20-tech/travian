import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WebViewModel()
    @StateObject private var spyBot = SpyAttackBot()
    @State private var showSettings = false
    @State private var showAutomationPanel = false
    @State private var showSpyPanel = false
    
    var body: some View {
        ZStack {
            // Main WebView
            WebViewContainer(viewModel: viewModel, spyBot: spyBot)
                .ignoresSafeArea(.container, edges: .bottom)
            
            // Loading indicator
            if viewModel.isLoading {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.5)
                        Spacer()
                    }
                    Spacer()
                }
                .background(Color.black.opacity(0.3))
            }
            
            // Floating automation button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    
                    VStack(spacing: 12) {
                        // Spy & Attack bot button
                        Button(action: {
                            showSpyPanel.toggle()
                        }) {
                            Image(systemName: "eye.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(spyBot.isScouting || spyBot.isAttacking ? .red : .white)
                                .shadow(radius: 5)
                        }
                        
                        // Automation toggle button
                        Button(action: {
                            showAutomationPanel.toggle()
                        }) {
                            Image(systemName: viewModel.isAutomationEnabled ? "bolt.circle.fill" : "bolt.circle")
                                .font(.system(size: 28))
                                .foregroundColor(viewModel.isAutomationEnabled ? .green : .white)
                                .shadow(radius: 5)
                        }
                        
                        // Settings button
                        Button(action: {
                            showSettings.toggle()
                        }) {
                            Image(systemName: "gear.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                                .shadow(radius: 5)
                        }
                        
                        // Refresh button
                        Button(action: {
                            viewModel.refresh()
                        }) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                                .shadow(radius: 5)
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 30)
                }
            }
            
            // Automation panel overlay
            if showAutomationPanel {
                AutomationPanelView(viewModel: viewModel, isPresented: $showAutomationPanel)
                    .transition(.move(edge: .bottom))
                    .animation(.spring(), value: showAutomationPanel)
            }
            
            // Spy & Attack panel overlay
            if showSpyPanel {
                SpyAttackPanelView(bot: spyBot, isPresented: $showSpyPanel)
                    .transition(.move(edge: .bottom))
                    .animation(.spring(), value: showSpyPanel)
            }
            
            // Settings panel overlay
            if showSettings {
                SettingsView(viewModel: viewModel, isPresented: $showSettings)
                    .transition(.move(edge: .bottom))
                    .animation(.spring(), value: showSettings)
            }
        }
        .alert("إشعار", isPresented: $viewModel.showAlert) {
            Button("حسناً") {}
        } message: {
            Text(viewModel.alertMessage)
        }
    }
}
