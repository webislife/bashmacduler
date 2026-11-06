import AppKit
import SwiftUI

@main
enum BashMacDulerApplication {
    static let delegate = AppDelegate()

    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        application.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = ScriptStore()
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var blinkTimer: Timer?
    private var blinkVisible = true

    private lazy var runner: ScriptRunner = {
        let runner = ScriptRunner(store: store)
        runner.onRunningCountChange = { [weak self] _ in
            self?.updateStatusIcon()
        }
        return runner
    }()

    private lazy var scheduler = ScriptScheduler(store: store, runner: runner)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusItem()
        setupWindow()

        NotificationManager.shared.requestAuthorization()
        scheduler.start()
        updateStatusIcon()
        showWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        scheduler.stop()
        blinkTimer?.invalidate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    @objc private func toggleWindow() {
        if window?.isVisible == true {
            window?.close()
        } else {
            showWindow()
        }
    }

    private func showWindow() {
        guard let window = window else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let applicationMenuItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(
            withTitle: "Выйти из BashMacDuler",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        applicationMenuItem.submenu = applicationMenu
        mainMenu.addItem(applicationMenuItem)
        NSApplication.shared.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleWindow)
    }

    private func setupWindow() {
        let contentView = ContentView(store: store, runner: runner)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BashMacDuler"
        window.contentViewController = NSHostingController(rootView: contentView)
        window.minSize = NSSize(width: 720, height: 460)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.setFrameAutosaveName("BashMacDulerMainWindow")
        window.center()
        window.delegate = self
        self.window = window
    }

    private func updateStatusIcon() {
        let runningCount = store.runningScriptIDs.count
        let isRunning = runningCount > 0
        let symbolName = isRunning ? "arrow.triangle.2.circlepath" : "terminal"

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "BashMacDuler") {
            image.isTemplate = true
            statusItem.button?.image = image
        }
        statusItem.button?.toolTip = isRunning
            ? "BashMacDuler — выполняется скриптов: \(runningCount)"
            : "BashMacDuler — нажмите, чтобы открыть"

        if isRunning {
            startBlinking()
        } else {
            stopBlinking()
        }
    }

    private func startBlinking() {
        guard blinkTimer == nil else { return }

        blinkVisible = true
        statusItem.button?.alphaValue = 1
        let timer = Timer(timeInterval: 0.45, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.blinkVisible.toggle()
            self.statusItem.button?.alphaValue = self.blinkVisible ? 1 : 0.25
        }
        RunLoop.main.add(timer, forMode: .common)
        blinkTimer = timer
    }

    private func stopBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        statusItem.button?.alphaValue = 1
    }
}
