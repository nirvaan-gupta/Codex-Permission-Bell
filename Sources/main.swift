import AppKit
import ApplicationServices
import UserNotifications
import Network
import ServiceManagement

let appID = "local.permissionbell.app"
let bridgePort: UInt16 = 18473
let bridgeToken = "__BRIDGE_TOKEN__"

struct Pending {
    let source: String
    let detail: String
    let bundle: String?
    var seen: Date
    var alerted: Date
    var misses: Int = 0
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var item: NSStatusItem!
    var window: NSWindow?
    var statusLabel: NSTextField?
    var timer: Timer?
    var pending: [String: Pending] = [:]
    var listener: NWListener?
    let scannerQueue = DispatchQueue(label: "permissionbell.scanner", qos: .utility)
    var scanning = false
    var paused = false
    var lastBrowser: Date = .distantPast
    var lastSound: Date = .distantPast
    var lastAX: Date = .distantPast
    var bridgeError: String?
    var notificationAllowed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: appID).count <= 1 else { NSApp.terminate(nil); return }
        UNUserNotificationCenter.current().delegate = self
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenu()
        startBridge()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.tick() }
        requestNotifications()
        if CommandLine.arguments.contains("--setup") || !UserDefaults.standard.bool(forKey: "onboarded") || !AXIsProcessTrusted() { showSetup() }
        tick()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSetup(); return true }
    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { allowed, _ in
            DispatchQueue.main.async { self.notificationAllowed = allowed; self.refreshStatus() }
        }
    }
    func updateMenu() {
        item.button?.image = NSImage(systemSymbolName: paused ? "bell.slash" : (pending.isEmpty ? "bell.badge" : "bell.badge.fill"), accessibilityDescription: "Permission Bell")
        let menu = NSMenu()
        menu.addItem(withTitle: paused ? "Monitoring paused" : "\(pending.count) approval(s) waiting", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        for (key, p) in pending.sorted(by: { $0.value.source < $1.value.source }).prefix(12) {
            let row = NSMenuItem(title: "Open \(p.source)", action: #selector(openPending(_:)), keyEquivalent: "")
            row.representedObject = key; row.target = self; menu.addItem(row)
        }
        for (title, action) in [("Setup & status…", #selector(showSetup)), ("Test sound & notification", #selector(testAlert)), (paused ? "Resume monitoring" : "Pause monitoring", #selector(togglePause)), ("Start at login", #selector(toggleLogin))] {
            let row = NSMenuItem(title: title, action: action, keyEquivalent: ""); row.target = self
            if title == "Start at login" { row.state = SMAppService.mainApp.status == .enabled ? .on : .off }
            menu.addItem(row)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Permission Bell", action: #selector(quitApp), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
        item.menu = menu
        refreshStatus()
    }
    @objc func quitApp() { NSApp.terminate(nil) }
    @objc func togglePause() { paused.toggle(); updateMenu() }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { showMessage("Login setting", error.localizedDescription) }
        updateMenu()
    }
    @objc func openPending(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let p = pending[key] else { return }
        if let bundle = p.bundle, let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first { app.activate(options: []) }
        else if let url = URL(string: "https://chatgpt.com") { NSWorkspace.shared.open(url) }
    }
    @objc func testAlert() { sendAlert(source: "Permission Bell", detail: "Test successful. Approval alerts will sound like this.", key: "test") }
    func sendAlert(source: String, detail: String, key: String) {
        let content = UNMutableNotificationContent()
        content.title = source == "Permission Bell" ? "Permission Bell is ready" : "\(source) needs your approval"
        content.body = detail
        // Play independently so alerts still make a sound when notification sounds are disabled.
        if Date().timeIntervalSince(lastSound) > 2 { NSSound(named: "Glass")?.play(); lastSound = Date() }
        content.userInfo = ["key": key]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .list]) }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let row = NSMenuItem(); row.representedObject = response.notification.request.content.userInfo["key"]; openPending(row); completionHandler()
    }
    func record(key: String, source: String, detail: String, bundle: String?) {
        let now = Date()
        if var p = pending[key] { p.seen = now; p.misses = 0; pending[key] = p }
        else {
            pending[key] = Pending(source: source, detail: detail, bundle: bundle, seen: now, alerted: paused ? .distantPast : now)
            if !paused { sendAlert(source: source, detail: detail, key: key) }
        }
    }
    func tick() {
        let now = Date()
        let stale = pending.filter { $0.key.hasPrefix("web:") && now.timeIntervalSince($0.value.seen) > 90 }.map(\.key)
        remove(stale)
        if !paused {
            for (key, var p) in pending where now.timeIntervalSince(p.alerted) >= 60 {
                sendAlert(source: p.source, detail: "Still waiting for approval. Open the app to respond.", key: key)
                p.alerted = now; pending[key] = p
            }
        }
        updateMenu()
        guard !scanning, AXIsProcessTrusted() else { return }
        scanning = true
        let skipBrowsers = now.timeIntervalSince(lastBrowser) < 60
        scannerQueue.async {
            let found = self.scan(skipBrowsers: skipBrowsers)
            DispatchQueue.main.async {
                self.lastAX = Date()
                for entry in found { self.record(key: entry.0, source: entry.1, detail: "An approval control is waiting. Open the app to review it.", bundle: entry.2) }
                let keys = Set(found.map { $0.0 })
                var gone: [String] = []
                for (key, var p) in self.pending where key.hasPrefix("ax:") && !keys.contains(key) {
                    p.misses += 1; self.pending[key] = p
                    if p.misses >= 3 { gone.append(key) }
                }
                self.remove(gone); self.scanning = false; self.updateMenu()
            }
        }
    }
    func remove(_ keys: [String]) {
        for key in keys { pending.removeValue(forKey: key) }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: keys)
    }
    func string(_ node: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(node, attribute as CFString, &value) == .success else { return "" }
        return value as? String ?? ""
    }
    func scan(skipBrowsers: Bool) -> [(String, String, String)] {
        let native = ["chatgpt", "codex", "claude", "com.microsoft.vscode"]
        let browsers = ["com.google.chrome", "com.apple.safari", "com.microsoft.edgemac", "company.thebrowser.browser", "org.mozilla.firefox", "com.brave.browser"]
        var result: [(String, String, String)] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let bundle = app.bundleIdentifier else { continue }
            let name = (app.localizedName ?? "").lowercased()
            let isNative = native.contains { bundle.lowercased().contains($0) || name.contains($0) }
            guard isNative || (browsers.contains(bundle.lowercased()) && !(skipBrowsers && bundle.lowercased() == "com.google.chrome")) else { continue }
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.2)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &value) == .success, let windows = value as? [AXUIElement] else { continue }
            let deadline = Date().addingTimeInterval(1.5)
            for (index, window) in windows.enumerated() {
                let title = string(window, kAXTitleAttribute)
                // Browsers are monitored only on AI pages; the extension covers hidden tabs.
                if !isNative && !["chatgpt", "codex", "claude"].contains(where: { title.lowercased().contains($0) }) { continue }
                var stack = [window]; var visited = 0; var buttons: [String] = []; var texts: [String] = []
                while let node = stack.popLast(), visited < 1800, Date() < deadline {
                    visited += 1
                    let role = string(node, kAXRoleAttribute)
                    let label = [string(node, kAXTitleAttribute), string(node, kAXDescriptionAttribute)].filter { !$0.isEmpty }.first ?? ""
                    if role == kAXButtonRole {
                        var enabled: CFTypeRef?
                        AXUIElementCopyAttributeValue(node, kAXEnabledAttribute as CFString, &enabled)
                        if (enabled as? Bool) != false { buttons.append(label) }
                    }
                    if texts.joined().count < 24000 {
                        texts.append(String(label.prefix(300)))
                        if role == kAXStaticTextRole { texts.append(String(string(node, kAXValueAttribute).prefix(500))) }
                    }
                    var children: CFTypeRef?
                    if AXUIElementCopyAttributeValue(node, kAXChildrenAttribute as CFString, &children) == .success, let nodes = children as? [AXUIElement] { stack.append(contentsOf: nodes.reversed()) }
                }
                let context = ApprovalDetection.hasRequestContext(texts.joined(separator: " "))
                if buttons.contains(where: { ApprovalDetection.isApprovalButton($0) || (context && ApprovalDetection.isGenericApproval($0)) }) {
                    result.append(("ax:\(app.processIdentifier):\(index)", app.localizedName ?? "AI app", bundle))
                }
            }
        }
        return result
    }
    func startBridge() {
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: bridgePort)!)
            listener = try NWListener(using: parameters)
            listener?.stateUpdateHandler = { state in
                if case .failed(let error) = state { DispatchQueue.main.async { self.bridgeError = error.localizedDescription; self.refreshStatus() } }
            }
            listener?.newConnectionHandler = { connection in
                connection.start(queue: .global(qos: .utility))
                self.receive(connection, data: Data())
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) { connection.cancel() }
            }
            listener?.start(queue: .global(qos: .utility))
        } catch { bridgeError = error.localizedDescription }
    }
    func receive(_ connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { chunk, _, complete, error in
            var data = data; if let chunk { data.append(chunk) }
            guard data.count <= 32768, error == nil else { connection.cancel(); return }
            guard let separator = data.range(of: Data("\r\n\r\n".utf8)), let headers = String(data: data[..<separator.lowerBound], encoding: .utf8) else {
                if !complete { self.receive(connection, data: data) } else { connection.cancel() }; return
            }
            let lines = headers.components(separatedBy: "\r\n")
            var fields: [String: String] = [:]
            for line in lines.dropFirst() { if let i = line.firstIndex(of: ":") { fields[String(line[..<i]).lowercased()] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces) } }
            let origin = fields["origin"] ?? ""
            guard origin.hasPrefix("chrome-extension://") || origin.hasPrefix("moz-extension://") else { self.respond(connection, code: "403 Forbidden", origin: "", body: "Forbidden"); return }
            let cors = "Access-Control-Allow-Origin: \(origin)\r\nAccess-Control-Allow-Methods: POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type, X-Permission-Bell-Token\r\nAccess-Control-Allow-Private-Network: true\r\n"
            if lines.first == "OPTIONS /event HTTP/1.1" { self.respond(connection, code: "204 No Content", origin: cors, body: ""); return }
            guard lines.first == "POST /event HTTP/1.1", fields["x-permission-bell-token"] == bridgeToken, let length = Int(fields["content-length"] ?? ""), length >= 0, length <= 16384 else { self.respond(connection, code: "403 Forbidden", origin: "", body: "Forbidden"); return }
            let body = data[separator.upperBound...]
            if body.count < length { if !complete { self.receive(connection, data: data) } else { connection.cancel() }; return }
            guard let event = try? JSONSerialization.jsonObject(with: Data(body.prefix(length))) as? [String: Any], let tab = event["tab"] as? Int, let active = event["pending"] as? Bool, let host = event["host"] as? String, ["chatgpt.com", "chat.openai.com", "claude.ai"].contains(host) else { self.respond(connection, code: "400 Bad Request", origin: cors, body: "Invalid event"); return }
            DispatchQueue.main.async {
                self.lastBrowser = Date()
                let key = "web:\(tab)"
                if active { self.record(key: key, source: host == "claude.ai" ? "Claude" : "ChatGPT", detail: "Approval is waiting in a browser tab. Open your browser to review it.", bundle: event["browser"] as? String) }
                else { self.remove([key]) }
                self.updateMenu()
            }
            self.respond(connection, code: "200 OK", origin: cors, body: "ok")
        }
    }
    func respond(_ connection: NWConnection, code: String, origin: String, body: String) {
        let response = "HTTP/1.1 \(code)\r\n\(origin)Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
    @objc func showSetup() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); refreshStatus(); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 485), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Permission Bell"; w.isReleasedWhenClosed = false; w.center()
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14; stack.translatesAutoresizingMaskIntoConstraints = false
        w.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: w.contentView!.leadingAnchor, constant: 26), stack.trailingAnchor.constraint(equalTo: w.contentView!.trailingAnchor, constant: -26), stack.topAnchor.constraint(equalTo: w.contentView!.topAnchor, constant: 25)])
        func label(_ text: String, size: CGFloat = 13) -> NSTextField { let l = NSTextField(wrappingLabelWithString: text); l.font = .systemFont(ofSize: size); return l }
        stack.addArrangedSubview(label("Hear when your AI needs you.", size: 25))
        stack.addArrangedSubview(label("Runs in the menu bar across windows and desktops. Plays a sound when an approval appears, then reminds you every minute until it clears."))
        let status = label(""); statusLabel = status; stack.addArrangedSubview(status)
        let actions: [(String, Selector)] = [("1. Enable Accessibility for native app monitoring", #selector(openAccessibility)), ("2. Enable notifications — choose Alerts for persistent banners", #selector(openNotifications)), ("3. Add browser extension for background ChatGPT / Claude tabs", #selector(openExtension)), ("Test sound & notification", #selector(testAlert)), ("Start at login", #selector(toggleLogin))]
        for (title, action) in actions { let b = NSButton(title: title, target: self, action: action); b.bezelStyle = .rounded; stack.addArrangedSubview(b) }
        stack.addArrangedSubview(label("Native monitoring: ChatGPT, Codex, Claude and VS Code. Browser extension: Chrome and Chromium browsers. Detection uses approval buttons; new app layouts may need updates. Sound requires audible system volume. Focus can suppress banners."))
        self.window = w; refreshStatus(); w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        UserDefaults.standard.set(true, forKey: "onboarded")
    }
    func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { self.notificationAllowed = settings.authorizationStatus == .authorized }
        }
        statusLabel?.stringValue = "Accessibility: \(AXIsProcessTrusted() ? "enabled" : "needs permission")   •   Notifications: \(notificationAllowed ? "enabled" : "needs permission")\nBrowser: \(bridgeError.map { "bridge error: \($0)" } ?? (Date().timeIntervalSince(lastBrowser) < 60 ? "connected" : "waiting for extension"))   •   \(paused ? "Paused" : "Monitoring")"
    }
    @objc func openAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func openNotifications() { requestNotifications(); NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!) }
    @objc func openExtension() {
        let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("browser-extension")
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
        showMessage("Add the browser extension", "In Chrome, open chrome://extensions, turn on Developer mode, choose Load unpacked, and select the browser-extension folder beside this app. Then reload your existing ChatGPT or Claude tabs. See README.md for details.")
    }
    func showMessage(_ title: String, _ message: String) { let a = NSAlert(); a.messageText = title; a.informativeText = message; a.runModal() }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
