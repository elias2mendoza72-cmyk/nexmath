import SwiftUI
import WebKit

struct ContentView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            WebView(url: URL(string: "https://nexmath.onrender.com")!)
                .ignoresSafeArea()

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            guard showSplash else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                withAnimation(.easeOut(duration: 0.3)) {
                    showSplash = false
                }
            }
        }
    }
}

struct SplashView: View {
    @State private var logoScale: CGFloat = 0.82
    @State private var logoOpacity = 0.0
    @State private var titleOffset: CGFloat = 12
    @State private var titleOpacity = 0.0
    @State private var titleScale: CGFloat = 0.98
    @State private var glowOpacity = 0.0
    @State private var glowScale: CGFloat = 0.9
    @State private var wobble = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.04, blue: 0.05), Color(red: 0.10, green: 0.10, blue: 0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.34, green: 0.24, blue: 0.92).opacity(0.35))
                .frame(width: 320, height: 320)
                .blur(radius: 28)
                .scaleEffect(glowScale)
                .opacity(glowOpacity)

            VStack(spacing: 14) {
                Image("NexMathLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 128, height: 128)
                    .shadow(color: Color(red: 0.13, green: 0.83, blue: 0.93, opacity: 0.35), radius: 18, x: 0, y: 10)
                    .scaleEffect(logoScale)
                    .rotationEffect(.degrees(wobble ? 2 : -2))
                    .offset(y: wobble ? -3 : 3)
                    .opacity(logoOpacity)

                Image("NexMathWordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 36)
                    .offset(y: titleOffset)
                    .scaleEffect(titleScale)
                    .opacity(titleOpacity)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.35)) {
                glowOpacity = 1.0
                glowScale = 1.0
            }
            withAnimation(.easeOut(duration: 0.35)) {
                titleOffset = 0
                titleOpacity = 1.0
                titleScale = 1.0
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                wobble.toggle()
            }
        }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        var parent: WebView

        init(_ parent: WebView) {
            self.parent = parent
        }

        // Handle camera/microphone permission requests from the web view
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            // Grant permission - iOS will still show system dialog if needed
            decisionHandler(.grant)
        }

        // Navigation error logging for debugging
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("Navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("Provisional navigation failed: \(error.localizedDescription)")
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        // Configure web view for media capture
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        webView.load(request)

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

#Preview {
    ContentView()
}
