import SwiftUI
import WebKit

struct GameCenterView: View {
    @State private var controller = WebController()

    // The site is light only: page background and navy taken from its stylesheet (rgb 244,247,251 and 4,30,66).
    private static let pageBackground = Color(red: 244 / 255, green: 247 / 255, blue: 251 / 255)
    private static let navy = Color(red: 4 / 255, green: 30 / 255, blue: 66 / 255)

    var body: some View {
        VStack(spacing: 0) {
            if controller.canGoBack {  // own bar, so the button never covers the page
                HStack {
                    Button { controller.goBack() } label: {
                        Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Back")
                    Spacer()
                }
                .tint(Self.navy)
            }
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
