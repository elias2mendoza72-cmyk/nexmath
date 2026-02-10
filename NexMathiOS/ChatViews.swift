import SwiftUI
import PhotosUI
import WebKit

struct ChatScreen: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var draftMessage = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showImagePreview = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.04, blue: 0.05), Color(red: 0.08, green: 0.08, blue: 0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HeaderView(
                    mode: viewModel.currentMode,
                    onProgressTap: { viewModel.showProgressSheet = true },
                    onNewSession: { viewModel.newSession() }
                )

                ModeSelectorView(currentMode: $viewModel.currentMode)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                Divider()
                    .overlay(Color.white.opacity(0.06))
                    .padding(.top, 12)

                MessagesView(messages: viewModel.messages, showEmptyState: viewModel.messages.isEmpty) {
                    if viewModel.currentMode == .explain {
                        ExplainActionsView(
                            onDeeper: { viewModel.sendExplainAction(.deeper) },
                            onDifferent: { viewModel.sendExplainAction(.differently) },
                            onVerify: { viewModel.sendExplainAction(.verify) }
                        )
                    } else {
                        EmptyView()
                    }
                }

                InputBar(
                    message: $draftMessage,
                    isLoading: viewModel.isLoading,
                    selectedImage: $selectedImage,
                    selectedItem: $selectedItem,
                    onSend: sendMessage
                )
            }
        }
        .sheet(isPresented: $viewModel.showProgressSheet) {
            ProgressSheet(progress: viewModel.progress)
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { _ in viewModel.errorMessage = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Something went wrong.")
        }
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                    showImagePreview = true
                }
            }
        }
    }

    private func sendMessage() {
        let message = draftMessage
        draftMessage = ""
        let image = selectedImage
        selectedImage = nil
        selectedItem = nil
        viewModel.send(message: message, image: image)
    }
}

struct HeaderView: View {
    let mode: ChatMode
    let onProgressTap: () -> Void
    let onNewSession: () -> Void

    var body: some View {
        HStack {
            Button(action: onProgressTap) {
                HStack(spacing: 8) {
                    Image("NexMathLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text("NexMath")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.35, green: 0.85, blue: 0.95), Color(red: 0.64, green: 0.39, blue: 0.96)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Text(mode.title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(
                    Capsule().fill(Color.white.opacity(0.06))
                )

            Spacer()

            Button(action: onNewSession) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("New")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

struct ModeSelectorView: View {
    @Binding var currentMode: ChatMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ChatMode.allCases) { mode in
                Button(action: { currentMode = mode }) {
                    Text(mode.title)
                        .font(.system(size: 14, weight: currentMode == mode ? .semibold : .regular))
                        .foregroundColor(currentMode == mode ? .white : Color.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(currentMode == mode ? Color.white.opacity(0.08) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

struct MessagesView<Actions: View>: View {
    let messages: [ChatMessage]
    let showEmptyState: Bool
    let actionsView: () -> Actions

    init(messages: [ChatMessage], showEmptyState: Bool, @ViewBuilder actionsView: @escaping () -> Actions) {
        self.messages = messages
        self.showEmptyState = showEmptyState
        self.actionsView = actionsView
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if showEmptyState {
                        EmptyStateView()
                    }

                    ForEach(messages) { message in
                        MessageRow(message: message)
                    }

                    if let last = messages.last, last.isExplainResponse {
                        actionsView()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .onChange(of: messages.count) { _, _ in
                guard let lastId = messages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            ForEach(ChatMode.allCases) { mode in
                VStack(alignment: .leading, spacing: 6) {
                    Text(mode.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text(mode.description)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
            }
        }
    }
}

struct MessageRow: View {
    let message: ChatMessage
    @State private var contentHeight: CGFloat = 40

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .assistant {
                HTMLMessageView(content: message.content, height: $contentHeight)
                    .frame(height: contentHeight)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                Spacer(minLength: 32)
            } else {
                Spacer(minLength: 32)
                Text(message.content)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(red: 0.62, green: 0.34, blue: 0.96).opacity(0.6))
                    )
            }
        }
        .id(message.id)
    }
}

struct ExplainActionsView: View {
    let onDeeper: () -> Void
    let onDifferent: () -> Void
    let onVerify: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("Explain differently", action: onDifferent)
            Button("Go deeper", action: onDeeper)
            Button("I understand", action: onVerify)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.white)
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .buttonStyle(.plain)
    }
}

struct InputBar: View {
    @Binding var message: String
    let isLoading: Bool
    @Binding var selectedImage: UIImage?
    @Binding var selectedItem: PhotosPickerItem?
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let selectedImage {
                HStack {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer()
                    Button("Remove") {
                        self.selectedImage = nil
                        self.selectedItem = nil
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
            }

            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 32, height: 32)
                }

                ZStack(alignment: .leading) {
                    if message.isEmpty {
                        Text("Ask a calculus question...")
                            .foregroundColor(.white.opacity(0.4))
                    }
                    TextEditor(text: $message)
                        .frame(minHeight: 36, maxHeight: 100)
                        .foregroundColor(.white)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                }

                Button(action: onSend) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(red: 0.62, green: 0.34, blue: 0.96))
                        )
                }
                .disabled(isLoading || (message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedImage == nil))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .padding(.horizontal, 16)

        }
        .padding(.top, 8)
        .background(Color.clear)
    }
}

struct ProgressSheet: View {
    let progress: [ProgressTopic: Bool]

    var body: some View {
        NavigationStack {
            List {
                ForEach(ProgressTopic.allCases) { topic in
                    HStack {
                        Text(topic.title)
                        Spacer()
                        if progress[topic] == true {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "circle")
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .navigationTitle("Progress")
        }
    }
}

struct HTMLMessageView: UIViewRepresentable {
    let content: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = HTMLBuilder.buildHTML(from: content)
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: HTMLMessageView
        var lastHTML: String?

        init(_ parent: HTMLMessageView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                if let height = result as? Double {
                    DispatchQueue.main.async {
                        self.parent.height = max(40, height)
                    }
                }
            }
        }
    }
}

enum HTMLBuilder {
    static func buildHTML(from markdown: String) -> String {
        let encoded = (try? JSONEncoder().encode(markdown))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""

        return """
        <!doctype html>
        <html>
        <head>
          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />
          <link rel=\"stylesheet\" href=\"https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css\">
          <style>
            body { margin: 0; color: #f8fafc; font: 15px -apple-system, BlinkMacSystemFont, 'Inter', 'Helvetica Neue', sans-serif; background: transparent; }
            p, li { line-height: 1.5; }
            img { max-width: 100%; border-radius: 12px; }
            code { background: rgba(255,255,255,0.08); padding: 2px 6px; border-radius: 6px; }
            pre { background: rgba(255,255,255,0.06); padding: 12px; border-radius: 12px; overflow-x: auto; }
            h1,h2,h3 { margin: 0.6em 0 0.4em; }
            .plot-container { margin: 12px 0; }
          </style>
        </head>
        <body>
          <div id=\"content\"></div>
          <script src=\"https://cdn.jsdelivr.net/npm/marked/marked.min.js\"></script>
          <script src=\"https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js\"></script>
          <script src=\"https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/contrib/auto-render.min.js\"></script>
          <script>
            const raw = \(encoded);
            const html = marked.parse(raw, { breaks: true, mangle: false, headerIds: false });
            const container = document.getElementById('content');
            container.innerHTML = html;
            renderMathInElement(container, {
              delimiters: [
                {left: '$$', right: '$$', display: true},
                {left: '$', right: '$', display: false},
                {left: '\\\\(', right: '\\\\)', display: false},
                {left: '\\\\[', right: '\\\\]', display: true}
              ]
            });
          </script>
        </body>
        </html>
        """
    }
}
