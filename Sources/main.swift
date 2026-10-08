import AppKit
import JavaScriptCore
import WebKit

// MARK: - Markdown rendering

/// Converts Markdown to HTML using the bundled marked.js, run in JavaScriptCore.
/// Rendering happens outside the web view so the web view can run with JavaScript disabled.
final class MarkdownRenderer {
    private let context = JSContext()!

    init() {
        guard let url = Bundle.main.url(forResource: "marked.min", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("marked.min.js missing from app bundle")
        }
        context.evaluateScript(source)
        context.evaluateScript("marked.setOptions({ gfm: true, breaks: false });")
    }

    func html(from markdown: String) -> String {
        let parse = context.objectForKeyedSubscript("marked").objectForKeyedSubscript("parse")!
        return parse.call(withArguments: [markdown])?.toString() ?? ""
    }
}

// MARK: - Viewer window

final class ViewerWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate {
    private let fileURL: URL
    private let webView: WKWebView
    private var tempHTML: URL?
    var onClose: ((ViewerWindowController) -> Void)?

    init(fileURL: URL, renderer: MarkdownRenderer) {
        self.fileURL = fileURL

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsMagnification = true

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = fileURL.lastPathComponent
        window.representedURL = fileURL
        window.contentView = webView
        window.setFrameAutosaveName("MDViewerWindow")
        super.init(window: window)

        window.delegate = self
        webView.navigationDelegate = self
        load(renderer: renderer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func load(renderer: MarkdownRenderer) {
        let markdown: String
        do {
            markdown = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            markdown = (try? String(contentsOf: fileURL, encoding: .isoLatin1))
                ?? "**Could not read file:** \(error.localizedDescription)"
        }

        let body = renderer.html(from: markdown)
        let baseHref = fileURL.deletingLastPathComponent().absoluteString
        let page = Self.template
            .replacingOccurrences(of: "{{TITLE}}", with: escapeHTML(fileURL.lastPathComponent))
            .replacingOccurrences(of: "{{BASE}}", with: escapeHTML(baseHref))
            .replacingOccurrences(of: "{{BODY}}", with: body)

        // Load from a temp file (rather than loadHTMLString) so relative local images resolve.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mdviewer-\(UUID().uuidString).html")
        do {
            try page.write(to: tmp, atomically: true, encoding: .utf8)
            tempHTML = tmp
            webView.loadFileURL(tmp, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        } catch {
            webView.loadHTMLString(page, baseURL: fileURL.deletingLastPathComponent())
        }
    }

    // Open clicked links in the default browser / app instead of navigating away.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard action.navigationType == .linkActivated, let url = action.request.url else {
            decisionHandler(.allow)
            return
        }
        if url.fragment != nil, url.path == tempHTML?.path {
            decisionHandler(.allow) // in-page anchor
            return
        }
        NSWorkspace.shared.open(url)
        decisionHandler(.cancel)
    }

    func windowWillClose(_ notification: Notification) {
        if let tempHTML { try? FileManager.default.removeItem(at: tempHTML) }
        onClose?(self)
    }

    private func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let template = """
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8">
    <base href="{{BASE}}">
    <title>{{TITLE}}</title>
    <style>
    :root { color-scheme: light dark; --fg:#1f2328; --bg:#ffffff; --muted:#59636e; --border:#d1d9e0; --code-bg:#f6f8fa; --link:#0969da; }
    @media (prefers-color-scheme: dark) {
      :root { --fg:#e6edf3; --bg:#0d1117; --muted:#9198a1; --border:#3d444d; --code-bg:#151b23; --link:#4493f8; }
    }
    html { background: var(--bg); }
    body { font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; color: var(--fg);
           background: var(--bg); max-width: 820px; margin: 0 auto; padding: 32px 40px 64px; word-wrap: break-word; }
    h1, h2, h3, h4, h5, h6 { margin: 1.5em 0 0.6em; line-height: 1.25; font-weight: 600; }
    h1 { font-size: 2em; padding-bottom: .3em; border-bottom: 1px solid var(--border); }
    h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid var(--border); }
    h3 { font-size: 1.25em; } h4 { font-size: 1em; } h5 { font-size: .875em; } h6 { font-size: .85em; color: var(--muted); }
    body > :first-child { margin-top: 0; }
    p, ul, ol, blockquote, pre, table { margin: 0 0 1em; }
    a { color: var(--link); text-decoration: none; } a:hover { text-decoration: underline; }
    code, pre { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.875em; }
    code { background: var(--code-bg); padding: .2em .4em; border-radius: 6px; }
    pre { background: var(--code-bg); padding: 16px; border-radius: 6px; overflow: auto; line-height: 1.45; }
    pre code { background: none; padding: 0; font-size: 100%; }
    blockquote { padding: 0 1em; color: var(--muted); border-left: .25em solid var(--border); margin-left: 0; }
    ul, ol { padding-left: 2em; } li + li { margin-top: .25em; }
    li input[type=checkbox] { margin: 0 .4em 0 -1.3em; }
    table { border-collapse: collapse; display: block; overflow: auto; }
    th, td { border: 1px solid var(--border); padding: 6px 13px; }
    th { font-weight: 600; background: var(--code-bg); }
    hr { border: 0; height: 1px; background: var(--border); margin: 24px 0; }
    img { max-width: 100%; }
    </style>
    </head>
    <body>
    {{BODY}}
    </body>
    </html>
    """
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var renderer = MarkdownRenderer()
    private var controllers: [ViewerWindowController] = []
    private var openedAny = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        // Launched without a file (e.g. double-clicked): offer an open panel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, !self.openedAny else { return }
            self.showOpenPanel(nil)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(open)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Finder Services entry point ("Render Markdown" in the right-click menu).
    @objc func openFiles(_ pboard: NSPasteboard, userData: String?,
                         error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pboard.readObjects(forClasses: [NSURL.self],
                                      options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        urls.forEach(open)
    }

    @objc func showOpenPanel(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.init(filenameExtension: "md")!, .init(filenameExtension: "markdown")!, .plainText]
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            panel.urls.forEach(open)
        } else if controllers.isEmpty {
            NSApp.terminate(nil)
        }
    }

    private func open(_ url: URL) {
        openedAny = true
        let controller = ViewerWindowController(fileURL: url, renderer: renderer)
        controller.onClose = { [weak self] closed in
            self?.controllers.removeAll { $0 === closed }
        }
        if let last = controllers.last?.window {
            controller.window?.setFrameTopLeftPoint(
                last.cascadeTopLeft(from: NSPoint(x: last.frame.minX, y: last.frame.maxY)))
        }
        controllers.append(controller)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Menu

func buildMainMenu() -> NSMenu {
    let main = NSMenu()

    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Quit MD Viewer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    main.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = appMenu

    let fileMenu = NSMenu(title: "File")
    fileMenu.addItem(withTitle: "Open…", action: #selector(AppDelegate.showOpenPanel(_:)), keyEquivalent: "o")
    fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    main.addItem(withTitle: "File", action: nil, keyEquivalent: "").submenu = fileMenu

    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = editMenu

    let windowMenu = NSMenu(title: "Window")
    windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = windowMenu
    NSApp.windowsMenu = windowMenu

    return main
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.mainMenu = buildMainMenu()
app.run()
