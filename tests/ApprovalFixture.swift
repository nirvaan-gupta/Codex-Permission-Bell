import AppKit
final class Fixture: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 480,height: 180), styleMask: [.titled,.closable], backing: .buffered, defer: false)
        window.title = "Permission Bell — detector test"
        window.isReleasedWhenClosed = false
        let label = NSTextField(wrappingLabelWithString: "Synthetic approval request for Permission Bell testing. No command will run. Click Allow once to clear this test.")
        label.frame = NSRect(x: 24,y: 80,width: 430,height: 70)
        window.contentView!.addSubview(label)
        let button = NSButton(title: "Allow once",target: self,action: #selector(resolve))
        button.frame = NSRect(x:24,y:24,width:130,height:32)
        window.contentView!.addSubview(button)
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func resolve() { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
let delegate = Fixture()
app.delegate = delegate
app.run()
