import SwiftUI
import WebKit
import UniformTypeIdentifiers

// The accepted v3 runtime and tiles are bundled locally. No remote site/login is used.
struct PlazaPanoramaScene: View {
    let onLab: () -> Void
    let onFactory: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var state = "正在载入广场全景…"
    @State private var reloadID = UUID()
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("返回入口") { dismiss() }.accessibilityIdentifier("plaza.panorama.close")
                Spacer()
                Text(state).font(.caption).lineLimit(1).accessibilityIdentifier("plaza.panorama.state")
                Spacer()
                Button("实验楼") { enter(onLab) }.accessibilityIdentifier("plaza.panorama.lab")
                Button("工坊") { enter(onFactory) }.accessibilityIdentifier("plaza.panorama.factory")
            }.buttonStyle(.bordered).frame(minHeight: 44).padding(.horizontal, 12).padding(.vertical, 5)
            LocalPlazaWebView(onState: { state = $0 }).id(reloadID)
                .accessibilityIdentifier("plaza.panorama.web")
        }.background(Color(red: 0.95, green: 0.95, blue: 0.92))
    }
    private func enter(_ action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: action)
    }
}

private struct LocalPlazaWebView: UIViewRepresentable {
    let onState: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onState: onState) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(context.coordinator.assets, forURLScheme: "citadel-plaza")
        config.userContentController.add(context.coordinator, name: "plazaState")
        let bridge = """
        (function(){
          var timer=setInterval(function(){
            var s=window.__plazaTest && window.__plazaTest.getState();
            if(!s)return;
            var mode=document.getElementById('tileMode').getAttribute('aria-pressed')==='true'?'图块全景':s.mode==='photo'?'有限视角原图':'球面全景';
            var stats=document.getElementById('tileHUD').textContent;
            window.webkit.messageHandlers.plazaState.postMessage({ready:s.mode==='photo' ? (document.getElementById('photo').complete && document.getElementById('photo').naturalWidth>0) : s.textureReady,mode:mode,stats:stats,yaw:s.sphere.yaw,pitch:s.sphere.pitch,zoom:s.mode==='photo'?s.photo.z:s.sphere.z});
          },800);
          addEventListener('pagehide',function(){clearInterval(timer)});
        })();
        """
        config.userContentController.addUserScript(WKUserScript(source: bridge, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.scrollView.isScrollEnabled = true
        web.scrollView.bounces = false
        web.isOpaque = false
        web.load(URLRequest(url: URL(string: "citadel-plaza://bundle/index.html?scene=tiles")!))
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "plazaState")
        uiView.navigationDelegate = nil
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let assets = BundledPlazaAssets()
        let onState: (String) -> Void
        init(onState: @escaping (String) -> Void) { self.onState = onState }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let data = message.body as? [String: Any], let mode = data["mode"] as? String else { return }
            let ready = data["ready"] as? Bool ?? false
            let yaw = (((data["yaw"] as? Double ?? 0) * 180 / .pi) + 360).truncatingRemainder(dividingBy: 360)
            let pitch = (data["pitch"] as? Double ?? 0) * 180 / .pi
            let zoom = ((data["zoom"] as? Double ?? 1) * 10).rounded(.toNearestOrAwayFromZero) / 10
            let stats = mode == "图块全景" ? " · " + (data["stats"] as? String ?? "") : ""
            if mode == "有限视角原图" {
                onState(String(format: "%@%@ · 原图内平移 · %.1f×", mode, ready ? "已就绪" : "载入中", zoom))
            } else {
                onState(String(format: "%@%@ · 水平 %.0f° / 俯仰 %.0f° · %.1f×", mode, ready ? "已就绪" : "载入中", yaw, pitch, zoom) + stats)
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onState("全景加载失败，可返回入口：" + error.localizedDescription) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onState("全景加载失败，可返回入口：" + error.localizedDescription) }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let scheme = navigationAction.request.url?.scheme
            decisionHandler(scheme == "citadel-plaza" || scheme == "about" ? .allow : .cancel)
        }
    }
}

private final class BundledPlazaAssets: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let root = Bundle.main.url(forResource: "PlazaV3", withExtension: nil) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let path = url.path.isEmpty ? "index.html" : String(url.path.dropFirst())
        let file = root.appendingPathComponent(path).standardizedFileURL
        guard file.path.hasPrefix(root.standardizedFileURL.path + "/"),
              ["html", "js", "css", "json", "png", "jpg"].contains(file.pathExtension),
              let bytes = try? Data(contentsOf: file) else {
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Access-Control-Allow-Origin": "*"])!
            urlSchemeTask.didReceive(response); urlSchemeTask.didFinish(); return
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime, "Content-Length": String(bytes.count), "Access-Control-Allow-Origin": "*", "Cache-Control": "no-store"])!
        urlSchemeTask.didReceive(response); urlSchemeTask.didReceive(bytes); urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

// Main-scene renderer: the accepted web camera interaction, without its demo menu.
struct RoamViewportPose: Codable {
    let mode: String
    let yaw: Double
    let pitch: Double
    let zoom: Double
    let photoX: Double
    let photoY: Double
    init?(_ message: [String: Any]) {
        guard let mode = message["mode"] as? String, ["sphere", "photo"].contains(mode),
              let yaw = message["yaw"] as? Double, let pitch = message["pitch"] as? Double,
              let zoom = message["zoom"] as? Double, let x = message["photoX"] as? Double,
              let y = message["photoY"] as? Double, [yaw,pitch,zoom,x,y].allSatisfy(\.isFinite) else { return nil }
        self.mode = mode; self.yaw = yaw; self.pitch = pitch; self.zoom = zoom; photoX = x; photoY = y
    }
}

struct EmbeddedSceneViewport: UIViewRepresentable {
    let source: RoamViewportSource
    let sceneName: String
    let initialPose: RoamViewportPose?
    let active: Bool
    let reset: Int
    let onUpdate: (RoamViewportPose?, String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(context.coordinator.assets, forURLScheme: "citadel-scene")
        config.userContentController.add(context.coordinator, name: "sceneViewport")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        view.isOpaque = false
        view.accessibilityIdentifier = "roam.viewport"
        var url = URLComponents()
        url.scheme = "citadel-scene"; url.host = "bundle"; url.path = "/SceneViewer25/index.html"
        switch source {
        case .plazaPanorama: url.queryItems = [URLQueryItem(name: "scene", value: "tiles")]
        case .photo(let asset): url.queryItems = [URLQueryItem(name: "scene", value: "photo"), URLQueryItem(name: "asset", value: asset)]
        }
        url.queryItems?.append(URLQueryItem(name: "title", value: sceneName))
        view.load(URLRequest(url: url.url!))
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard coordinator.loaded else { return }
        if coordinator.lastActive != active {
            coordinator.lastActive = active
            view.evaluateJavaScript("window.__sceneViewport?.setActive(\(active ? "true" : "false"))")
        }
        if coordinator.lastReset != reset {
            coordinator.lastReset = reset
            view.evaluateJavaScript("window.__sceneViewport?.reset()")
        }
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.evaluateJavaScript("window.__sceneViewport?.setActive(false)")
        view.stopLoading(); view.navigationDelegate = nil
        view.configuration.userContentController.removeScriptMessageHandler(forName: "sceneViewport")
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: EmbeddedSceneViewport
        let restoringPose: RoamViewportPose?
        fileprivate let assets = EmbeddedSceneAssets()
        var loaded = false
        var lastActive: Bool
        var lastReset: Int
        init(_ parent: EmbeddedSceneViewport) {
            self.parent = parent; restoringPose = parent.initialPose; lastActive = parent.active; lastReset = parent.reset
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            if let pose = restoringPose, let data = try? JSONEncoder().encode(pose), let json = String(data: data, encoding: .utf8) {
                webView.evaluateJavaScript("window.__sceneViewport?.restorePose(\(json))")
            }
            lastActive = parent.active
            webView.evaluateJavaScript("window.__sceneViewport?.setActive(\(parent.active ? "true" : "false"))")
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard loaded, message.frameInfo.isMainFrame, let data = message.body as? [String: Any],
                  let pose = RoamViewportPose(data) else { return }
            guard data["ready"] as? Bool == true else { parent.onUpdate(nil, "正在载入可拖动场景…"); return }
            let renderer = data["renderer"] as? String ?? ""
            if pose.mode == "sphere" {
                let yaw = (pose.yaw * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
                let pitch = pose.pitch * 180 / .pi
                parent.onUpdate(pose, String(format: "360° 环顾 · 水平 %.0f° / 俯仰 %.0f° · %.1f× · %@", yaw, pitch, pose.zoom, renderer))
            } else {
                parent.onUpdate(pose, String(format: "原图内平移 · %.1f× · 拖动不改变当前位置", pose.zoom))
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { parent.onUpdate(nil, "场景加载失败，可退出后重试：" + error.localizedDescription) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { parent.onUpdate(nil, "场景加载失败，可退出后重试：" + error.localizedDescription) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { loaded = false; parent.onUpdate(nil, "渲染进程已暂停，返回后可重新进入场景") }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let scheme = navigationAction.request.url?.scheme
            decisionHandler(scheme == "citadel-scene" || scheme == "about" ? .allow : .cancel)
        }
    }
}

/// This scheme exposes only existing bundled scene assets, never user files or remote URLs.
private final class EmbeddedSceneAssets: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { task.didFailWithError(URLError(.badURL)); return }
        let parts = url.pathComponents.filter { $0 != "/" }
        var file: URL?
        if parts.count == 2, parts[0] == "asset", parts[1].hasSuffix(".png") {
            let name = String(parts[1].dropLast(4))
            if name.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil { file = Bundle.main.url(forResource: name, withExtension: "png") }
        } else if let folder = parts.first, ["PlazaV3", "SceneViewer25"].contains(folder), parts.count > 1,
                  let root = Bundle.main.url(forResource: folder, withExtension: nil) {
            let candidate = root.appendingPathComponent(parts.dropFirst().joined(separator: "/")).standardizedFileURL
            if candidate.path.hasPrefix(root.standardizedFileURL.path + "/"), ["html", "css", "js", "json", "png", "jpg"].contains(candidate.pathExtension) { file = candidate }
        }
        guard let file, let bytes = try? Data(contentsOf: file) else {
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Access-Control-Allow-Origin": "*"])!
            task.didReceive(response); task.didFinish(); return
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime, "Content-Length": String(bytes.count), "Access-Control-Allow-Origin": "*", "Cache-Control": "no-store"])!
        task.didReceive(response); task.didReceive(bytes); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
