import Cocoa
import SwiftUI

// Coordinates are in AppKit's shared desktop space, including secondary displays.
struct PopupLayout {
    static func contentSize(in visibleFrame: NSRect) -> NSSize {
        NSSize(width: min(380, max(1, visibleFrame.width - 42)),
               height: min(700, max(1, visibleFrame.height - 42)))
    }
    static func fit(_ frame: NSRect, inside visibleFrame: NSRect) -> NSRect {
        let safe = visibleFrame.insetBy(dx: 8, dy: 8)
        let width = min(frame.width, safe.width)
        let height = min(frame.height, safe.height)
        return NSRect(x: min(max(frame.minX, safe.minX), safe.maxX - width),
                      y: min(max(frame.minY, safe.minY), safe.maxY - height),
                      width: width, height: height)
    }
}
struct DashboardViewport: View {
    @ObservedObject var monitor: Monitor
    let size: NSSize
    let settingsChanged: () -> Void
    var body: some View {
        ScrollView(.vertical) {
            Dashboard(monitor: monitor, settingsChanged: settingsChanged)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(Color(red: 0.055, green: 0.065, blue: 0.085))
        .preferredColorScheme(.dark)
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = Monitor()
    var item: NSStatusItem!
    let popover = NSPopover()
    var previewWindow: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName:"waveform.path.ecg",accessibilityDescription:"Pulse")
        item.button?.imagePosition = .imageLeading
        item.button?.font = .monospacedDigitSystemFont(ofSize:12,weight:.medium)
        item.button?.target = self; item.button?.action = #selector(toggle)
        item.button?.sendAction(on:[.leftMouseUp,.rightMouseUp])
        item.button?.setAccessibilityLabel("Pulse: мониторинг системы")
        popover.behavior = .transient
        popover.animates = false
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        monitor.onUpdate = { [weak self] in self?.updateTitle() }
        monitor.start(interval:UserDefaults.standard.object(forKey:"refreshInterval") as? Double ?? 2)
        if CommandLine.arguments.contains("--preview") {
            let controller = NSHostingController(rootView:Dashboard(monitor:monitor,settingsChanged:{}))
            let window = NSWindow(contentViewController:controller)
            window.styleMask = [.titled,.closable]; window.title = "Pulse · Preview"; window.center(); window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps:true); previewWindow = window
            DispatchQueue.main.asyncAfter(deadline:.now()+6) {
                let view = controller.view
                view.layoutSubtreeIfNeeded()
                if let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) {
                    view.cacheDisplay(in:view.bounds,to:bitmap)
                    if let data = bitmap.representation(using:.png,properties:[:]) { try? data.write(to:URL(fileURLWithPath:NSHomeDirectory()+"/Projects/Pulse/preview.png")) }
                }
            }
        } else if CommandLine.arguments.contains("--check-layout") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.openPopover()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard let window = self.popover.contentViewController?.view.window,
                          let screen = self.item.button?.window?.screen else { exit(1) }
                    let safe = screen.visibleFrame.insetBy(dx: 7, dy: 7)
                    print("Screen: \(screen.localizedName); visible: \(screen.visibleFrame); popup: \(window.frame)")
                    guard safe.contains(window.frame) else { print("FAIL: popup outside screen"); exit(1) }
                    print("PASS: actual popover is entirely inside its screen")
                    self.popover.performClose(nil)
                    self.checkDisplayLayout(index: 0)
                }
            }
        } else if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline:.now()+0.8) { self.toggle() }
        }
    }
    func updateTitle() {
        let s = monitor.sample
        let extra = UserDefaults.standard.bool(forKey:"showCPU") ? String(format:"  ·  %.0f%%",s.cpu) : ""
        item.button?.title = " \(degrees(s.cpuTemp))\(extra)"
        item.button?.toolTip = "Pulse · CPU \(degrees(s.cpuTemp))C · GPU \(degrees(s.gpuTemp))C\nНажмите, чтобы открыть мониторинг"
    }
    @objc func toggle() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle:"Открыть Pulse",action:#selector(openPopover),keyEquivalent:"").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle:"Завершить Pulse",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
            item.menu = menu; item.button?.performClick(nil); item.menu = nil
            return
        }
        if popover.isShown { popover.performClose(nil) } else { openPopover() }
    }
    @objc func openPopover() {
        guard let button = item.button else { return }
        presentPopover(relativeTo: button)
    }
    private func presentPopover(relativeTo button: NSView) {
        guard let screen = button.window?.screen ?? NSScreen.main else { return }
        let size = PopupLayout.contentSize(in: screen.visibleFrame)
        let controller = NSHostingController(rootView: DashboardViewport(
            monitor: monitor, size: size, settingsChanged: { [weak self] in self?.updateTitle() }))
        controller.sizingOptions = []
        controller.preferredContentSize = size
        popover.contentViewController = controller
        popover.contentSize = size
        NSApp.activate(ignoringOtherApps:true)
        popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY)
        fitPopoverToScreen(screen)
        // AppKit can finish positioning a popover on the following run-loop pass.
        DispatchQueue.main.async { [weak self] in self?.fitPopoverToScreen(screen) }
        popover.contentViewController?.view.window?.makeKey()
    }
    private func fitPopoverToScreen(_ screen: NSScreen) {
        guard popover.isShown, let window = popover.contentViewController?.view.window else { return }
        let fitted = PopupLayout.fit(window.frame, inside: screen.visibleFrame)
        if window.frame != fitted { window.setFrame(fitted, display: true) }
    }
    private func checkDisplayLayout(index: Int) {
        guard index < NSScreen.screens.count else { NSApp.terminate(nil); return }
        let screen = NSScreen.screens[index]
        let anchorWindow = NSWindow(contentRect: NSRect(x: screen.frame.maxX - 100,
            y: screen.visibleFrame.maxY - 22, width: 80, height: 22),
            styleMask: .borderless, backing: .buffered, defer: false)
        anchorWindow.isReleasedWhenClosed = false
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 22))
        anchorWindow.contentView = anchor
        anchorWindow.orderFrontRegardless()
        presentPopover(relativeTo: anchor)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let window = self.popover.contentViewController?.view.window else { exit(1) }
            print("Display test: \(screen.localizedName); visible: \(screen.visibleFrame); popup: \(window.frame)")
            guard screen.visibleFrame.insetBy(dx: 7, dy: 7).contains(window.frame) else { exit(1) }
            if index == NSScreen.screens.count - 1,
               let view = self.popover.contentViewController?.view,
               let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to:
                    URL(fileURLWithPath: NSHomeDirectory() + "/Projects/Pulse/layout-check.png"))
            }
            self.popover.performClose(nil)
            anchorWindow.close()
            print("PASS: display \(index + 1)")
            self.checkDisplayLayout(index: index + 1)
        }
    }
    @objc private func displaysChanged() {
        // The next opening recalculates both size and position for the new display.
        if popover.isShown { popover.performClose(nil) }
    }
}
if CommandLine.arguments.contains("--test-layout") {
    let displays = [NSRect(x: 0, y: 94, width: 1920, height: 956),
                    NSRect(x: 1920, y: 0, width: 1470, height: 924),
                    NSRect(x: -1440, y: 200, width: 1440, height: 680),
                    NSRect(x: 0, y: -900, width: 1280, height: 700)]
    for display in displays {
        let size = PopupLayout.contentSize(in: display)
        for x in [display.minX - 200, display.midX, display.maxX - 100] {
            for y in [display.minY - 300, display.maxY + 300] {
                let frame = NSRect(x: x, y: y, width: size.width + 26, height: size.height + 26)
                let fitted = PopupLayout.fit(frame, inside: display)
                precondition(display.insetBy(dx: 7, dy: 7).contains(fitted))
                precondition(fitted.size == frame.size, "Content must fit without clipping")
            }
        }
    }
    print("PASS: 24 placements across 4 display arrangements, including negative origins and small screens")
} else if CommandLine.arguments.contains("--diagnose") {
    let reader = MetricsReader()
    _ = reader.read()
    Thread.sleep(forTimeInterval:1)
    let s = reader.read()
    var result: [String:Any] = ["cpuPercent":s.cpu,"memoryUsedGB":s.memory/1_073_741_824,"memoryTotalGB":s.memoryTotal/1_073_741_824,"memoryPressure":s.pressure,"swapGB":s.swap/1_073_741_824,"downloadBytesPerSecond":s.down,"uploadBytesPerSecond":s.up,"sensors":s.sensors.map { ["key":$0.id,"name":$0.name,"celsius":$0.value] as [String:Any] }]
    result["cpuCelsius"] = s.cpuTemp; result["gpuCelsius"] = s.gpuTemp; result["gpuPercent"] = s.gpu; result["batteryPercent"] = s.battery; result["diskFreeGB"] = s.diskFree.map { $0/1_000_000_000 }
    if let data = try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]), let json = String(data:data,encoding:.utf8) { print(json) }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
