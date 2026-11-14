import SwiftUI
import WebKit

struct GameCenterView: View {
    @State private var controller = WebController()
    @AppStorage(AppearanceSetting.storageKey) private var stored = AppearanceSetting.system.rawValue
    // With "System" no override is set, so this is the system's appearance.
    @Environment(\.colorScheme) private var colorScheme

    private var setting: AppearanceSetting { AppearanceSetting(stored: stored) }
    private var isDark: Bool { setting.isDark(systemIsDark: colorScheme == .dark) }

    var body: some View {
        ZStack {
            WebViewContainer(webView: controller.webView)
                .ignoresSafeArea(edges: .bottom)
            if controller.state == .failed {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.slash").font(.largeTitle)
                    Text("The Game Center could not be loaded.")
                    Button("Retry") { controller.reload() }.buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
            } else if controller.state == .loading {
                ProgressView().controlSize(.large)
            }
        }
        // The status area shows the page color, so it matches the site in both modes.
        .background(Color(isDark ? DarkTheme.pageBackground : DarkTheme.lightPageBackground).ignoresSafeArea())
        .preferredColorScheme(setting.colorScheme)
        .onAppear {
            NotificationRouter.shared.onOpen = { controller.open($0) }
            controller.start(dark: isDark)
        }
        .onChange(of: WatchStore.shared.pages) { _, _ in controller.syncPageState() }   // e.g. a page was stopped in the settings
        .onChange(of: isDark) { _, dark in controller.setDark(dark) }
        .sheet(isPresented: $controller.showSettings) {
            SettingsView(stored: $stored).presentationDetents([.large])
        }
    }
}

private struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
