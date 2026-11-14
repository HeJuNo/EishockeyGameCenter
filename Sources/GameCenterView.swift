import SwiftUI
import WebKit

struct GameCenterView: View {
    @State private var controller = WebController()

    // The site is light only: its page background is rgb(244, 247, 251).
    private static let pageBackground = Color(red: 244 / 255, green: 247 / 255, blue: 251 / 255)

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
        .background(Self.pageBackground.ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}

private struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
