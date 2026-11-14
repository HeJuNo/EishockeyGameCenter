import SwiftUI
import WebKit

struct GameCenterView: View {
    @State private var controller = WebController()

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
        .overlay(alignment: .topLeading) {
            if controller.canGoBack {
                Button { controller.goBack() } label: {
                    Image(systemName: "chevron.left").font(.headline).padding(12)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("Back")
                .padding(.leading, 12)
            }
        }
    }
}

private struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
