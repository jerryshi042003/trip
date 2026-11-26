import SwiftUI
import WebKit

struct OfficialYouTubeVideo: Identifiable {
    let id: String
    let start: Int
    let playOnOpen: Bool

    init?(id: String, start: Double?, playOnOpen: Bool = false) {
        guard id.utf8.count == 11, id.utf8.allSatisfy({
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }) else { return nil }
        self.id = id
        self.start = max(0, start.flatMap { Int(exactly: $0.rounded(.down)) } ?? 0)
        self.playOnOpen = playOnOpen
    }
}

struct OfficialYouTubePlayer: View {
    let video: OfficialYouTubeVideo
    var download: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var status = Status.loading
    #if DEBUG
    @State private var playbackTime: Double?
    #endif

    private enum Status { case loading, ready, failed }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Text("Done").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityIdentifier("closeOfficialYouTube")
                Spacer()
            }
            .padding(.horizontal, 24)
            .foregroundStyle(.white)

            if status == .failed {
                VStack(spacing: 16) {
                    Text("This video couldn’t start.")
                        .accessibilityIdentifier("officialYouTubeUnavailable")
                    if let download {
                        Button("Download to Film Scrub", action: download)
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("downloadOfficialYouTube")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack {
                    OfficialYouTubeWebView(video: video, readyToStart: status == .ready) { event in
                        guard status != .failed else { return }
                        switch event {
                        case .ready: status = .ready
                        case .failed: status = .failed
                        case .playing(let time):
                            status = .ready
                            #if DEBUG
                            playbackTime = time
                            #endif
                        }
                    }
                    .opacity(status == .loading ? 0 : 1)
                    .accessibilityHidden(status == .loading)

                    if status == .loading {
                        ProgressView("Opening video")
                    }
                }
            }

        }
        .foregroundStyle(.white)
        .background(Color.black.ignoresSafeArea())
        #if DEBUG
        .overlay(alignment: .bottom) {
            if ProcessInfo.processInfo.arguments.contains("-testOfficialYouTubePlayback"), status == .ready {
                Text(playbackTime.map { String(format: "%.2f", $0) } ?? "Ready")
                    .foregroundStyle(.clear)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("officialYouTubePlaybackTime")
            }
        }
        #endif
        .task {
            do { try await Task.sleep(for: .seconds(20)) }
            catch { return }
            if status == .loading { status = .failed }
        }
    }
}

private struct OfficialYouTubeWebView: UIViewRepresentable {
    let video: OfficialYouTubeVideo
    let readyToStart: Bool
    let onEvent: (Event) -> Void

    enum Event { case ready, playing(Double), failed }

    func makeCoordinator() -> Coordinator { Coordinator(onEvent: onEvent) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = video.playOnOpen ? [] : .all
        configuration.userContentController.add(context.coordinator, name: "officialPlayer")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        guard let identifier = Bundle.main.bundleIdentifier,
              let origin = URL(string: "https://" + identifier.lowercased()) else {
            Task { @MainActor in onEvent(.failed) }
            return web
        }

        // Use YouTube’s normal controls and identify the app in the WebView Referer.
        web.loadHTMLString("""
        <!doctype html>
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body,#video{width:100%;height:100%;margin:0;background:#000}</style></head>
        <body><div id="video"></div>
        <script>
        function report(event, seconds) {
          window.webkit.messageHandlers.officialPlayer.postMessage({event, seconds});
        }
        let player;
        function startWhenVisible() {
          const visibility = new IntersectionObserver(([entry]) => {
            if (document.hidden || entry.intersectionRatio <= 0.5) return;
            visibility.disconnect();
            player.playVideo();
          }, { threshold: [0.51] });
          visibility.observe(player.getIframe());
        }
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('video', {
            videoId:'\(video.id)',
            playerVars:{start:\(video.start),playsinline:1,origin:'\(origin.absoluteString)'},
            events:{
              onReady: () => report('ready', 0),
              onError: () => report('failed', 0),
              onStateChange: e => {
                if (e.data === YT.PlayerState.PLAYING) report('playing', e.target.getCurrentTime());
              }
            }
          });
        }
        </script><script src="https://www.youtube.com/iframe_api"></script></body></html>
        """, baseURL: origin)
        return web
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard video.playOnOpen, readyToStart, view.window != nil, !context.coordinator.requestedPlayback else { return }
        context.coordinator.requestedPlayback = true
        view.evaluateJavaScript("requestAnimationFrame(() => requestAnimationFrame(startWhenVisible));")
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.pauseAllMediaPlayback(completionHandler: nil)
        view.stopLoading()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "officialPlayer")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onEvent: (Event) -> Void
        var requestedPlayback = false

        init(onEvent: @escaping (Event) -> Void) { self.onEvent = onEvent }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "officialPlayer", message.frameInfo.isMainFrame,
                  let body = message.body as? [String: Any], let event = body["event"] as? String else { return }
            switch event {
            case "ready": onEvent(.ready)
            case "playing":
                if let time = body["seconds"] as? Double, time.isFinite { onEvent(.playing(time)) }
            case "failed": onEvent(.failed)
            default: break
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let opensNewWindow = action.targetFrame == nil
            let leavesPlayer = action.targetFrame?.isMainFrame == true && action.navigationType == .linkActivated
            decisionHandler(opensNewWindow || leavesPlayer ? .cancel : .allow)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onEvent(.failed)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onEvent(.failed)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            onEvent(.failed)
        }
    }
}
