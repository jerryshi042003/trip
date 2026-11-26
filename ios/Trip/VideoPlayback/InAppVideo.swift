import AVKit
import SwiftUI
import WebKit

enum InAppVideo: Identifiable {
    case youtube(OfficialYouTubeVideo)
    case instagram(URL)
    case direct(URL)

    var id: String {
        switch self {
        case .youtube(let video): "youtube:\(video.id):\(video.start)"
        case .instagram(let url), .direct(let url): url.absoluteString
        }
    }

    init?(url: URL) {
        guard let address = Self.sourceURL(url),
              let parts = URLComponents(url: address, resolvingAgainstBaseURL: false),
              let host = parts.host?.lowercased() else { return nil }
        let path = parts.path.split(separator: "/")
        let query = parts.queryItems ?? []
        if ["youtube.com", "www.youtube.com", "m.youtube.com", "www.youtube-nocookie.com", "youtu.be"].contains(host) {
            let videoID: String?
            if host == "youtu.be", path.count == 1 {
                videoID = path.first.map(String.init)
            } else if path == ["watch"] {
                videoID = query.first { $0.name == "v" }?.value
            } else if path.count == 2, ["embed", "shorts", "live"].contains(path[0]) {
                videoID = String(path[1])
            } else {
                videoID = nil
            }
            let offset = query.first { ["t", "start"].contains($0.name) }?.value
                ?? parts.fragment.flatMap { $0.hasPrefix("t=") ? String($0.dropFirst(2)) : nil }
            guard let videoID, let video = OfficialYouTubeVideo(id: videoID, start: offset.flatMap(Self.seconds)) else { return nil }
            self = .youtube(video)
        } else if ["instagram.com", "www.instagram.com"].contains(host), path.count == 2,
                  ["reel", "p", "tv"].contains(path[0]),
                  path[1].wholeMatch(of: #/[A-Za-z0-9_-]+/#) != nil,
                  let embed = URL(string: "https://www.instagram.com/\(path[0])/\(path[1])/embed/") {
            self = .instagram(embed)
        } else if ["mp4", "mov", "m4v", "m3u8"].contains(address.pathExtension.lowercased()) {
            self = .direct(address)
        } else {
            return nil
        }
    }

    private static func sourceURL(_ url: URL) -> URL? {
        var address = url
        if url.scheme == "filmscrub", url.host == "open" {
            guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value,
                  let source = URL(string: value) else { return nil }
            address = source
        }
        guard ["https", "http"].contains(address.scheme?.lowercased() ?? ""),
              address.user == nil, address.password == nil else { return nil }
        return address
    }

    private static func seconds(_ text: String) -> Double? {
        if let seconds = Double(text), seconds.isFinite, seconds >= 0 { return seconds }
        guard !text.isEmpty,
              let time = text.wholeMatch(of: #/(?:(\d{1,3})h)?(?:(\d{1,4})m)?(?:(\d{1,6})s)?/#) else { return nil }
        return (time.1.flatMap { Double($0) } ?? 0) * 3600
            + (time.2.flatMap { Double($0) } ?? 0) * 60
            + (time.3.flatMap { Double($0) } ?? 0)
    }
}

struct InAppVideoButton<Label: View>: View {
    let url: URL
    @ViewBuilder let label: () -> Label
    @State private var video: InAppVideo?
    @State private var unavailable = false

    var body: some View {
        Button {
            if let item = InAppVideo(url: url) { video = item }
            else { unavailable = true }
        } label: {
            label()
        }
        .fullScreenCover(item: $video) { InAppVideoPlayer(video: $0) }
        .alert("This video couldn’t start.", isPresented: $unavailable) {
            Button("OK", role: .cancel) {}
        }
    }
}

struct InAppVideoPlayer: View {
    let video: InAppVideo

    var body: some View {
        switch video {
        case .youtube(let clip):
            OfficialYouTubePlayer(video: clip)
        case .instagram(let url):
            VideoStage {
                InstagramVideo(url: url)
            }
        case .direct(let url):
            VideoStage {
                DirectVideo(url: url)
            }
        }
    }
}

private struct VideoStage<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Done") { dismiss() }
                    .frame(minWidth: 44, minHeight: 44)
                Spacer()
            }
            .padding(.horizontal, 24)
            content()
        }
        .foregroundStyle(.white)
        .background(Color.black.ignoresSafeArea())
    }
}

private struct DirectVideo: View {
    @State private var player: AVPlayer

    init(url: URL) {
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .onDisappear { player.pause() }
    }
}

private struct InstagramVideo: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .black
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.pauseAllMediaPlayback(completionHandler: nil)
        web.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let url: URL
        private var showingError = false

        init(url: URL) { self.url = url }

        func webView(_ web: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let frame = action.targetFrame else { decisionHandler(.cancel); return }
            guard frame.isMainFrame else { decisionHandler(.allow); return }
            let target = action.request.url
            if showingError, target?.absoluteString == "about:blank" {
                decisionHandler(.allow)
                return
            }
            decisionHandler(target?.scheme == "https" && target?.host == url.host && target?.path == url.path
                && action.navigationType != .linkActivated ? .allow : .cancel)
        }

        func webView(_ web: WKWebView, decidePolicyFor response: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if response.isForMainFrame, let http = response.response as? HTTPURLResponse, http.statusCode >= 400 {
                decisionHandler(.cancel)
                showUnavailable(in: web)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ web: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            showUnavailable(in: web)
        }

        private func showUnavailable(in web: WKWebView) {
            showingError = true
            web.loadHTMLString("""
                <meta name="viewport" content="width=device-width">
                <body style="background:#000;color:#fff;font:17px -apple-system;padding:24px">
                This Instagram video couldn’t start.
                """, baseURL: nil)
        }
    }
}
