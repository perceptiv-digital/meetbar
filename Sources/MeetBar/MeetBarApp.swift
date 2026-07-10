import AppKit
import SwiftUI

extension Notification.Name {
    static let meetBarPopoverDidOpen = Notification.Name("digital.perceptiv.meetbar.popover-did-open")
}

@main
struct MeetBarApp: App {
    @NSApplicationDelegateAdaptor(MeetBarAppDelegate.self) private var appDelegate
    @State private var insertsLifecycleHost = false

    var body: some Scene {
        MenuBarExtra(isInserted: $insertsLifecycleHost) {
            EmptyView()
        } label: {
            EmptyView()
        }

        Settings {
            SettingsView()
                .environmentObject(appDelegate.model)
        }
    }
}

@MainActor
final class MeetBarAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSPopoverDelegate {
    let model = AppModel()

    private var statusItem: NSStatusItem?
    private var contextMenu: NSMenu?
    private var interactionView: StatusItemInteractionView?
    private let popover = NSPopover()
    private var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.arguments.contains("--preview-window") {
            showPreviewWindow()
            return
        }

        configurePopover()
        configureStatusItem()
    }

    private func configurePopover() {
        let content = MeetBarPopover()
            .environmentObject(model)
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }

        let renderer = ImageRenderer(
            content: MeetBarMenuBarMark()
                .foregroundStyle(Color.primary)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        button.image = renderer.nsImage
        button.image?.isTemplate = true
        button.imagePosition = .imageOnly
        button.toolTip = "MeetBar"
        button.setAccessibilityLabel("MeetBar")
        statusItem = item

        let interaction = StatusItemInteractionView(frame: button.bounds)
        interaction.autoresizingMask = [.width, .height]
        interaction.onLeftClick = { [weak self, weak button] in
            guard let self, let button else { return }
            self.togglePopover(from: button)
        }
        interaction.contextMenuProvider = { [weak self, weak button] in
            guard let self, let button else { return nil }
            self.popover.performClose(nil)
            button.highlight(true)
            return self.makeContextMenu()
        }
        button.addSubview(interaction)
        interactionView = interaction
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover(from: button)
        }
    }

    private func showPopover(from button: NSStatusBarButton) {
        button.highlight(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .meetBarPopoverDidOpen, object: nil)
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()

        let newMeeting = NSMenuItem(
            title: "New Meeting…",
            action: #selector(openMeetBar),
            keyEquivalent: "n"
        )
        newMeeting.target = self
        menu.addItem(newMeeting)

        let copyLast = NSMenuItem(
            title: "Copy Last Meeting Link",
            action: #selector(copyLastMeetingLink),
            keyEquivalent: "c"
        )
        copyLast.target = self
        copyLast.isEnabled = model.mostRecentMeetingURL != nil
        menu.addItem(copyLast)

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Development"
        let versionItem = NSMenuItem(title: "MeetBar \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit MeetBar",
            action: #selector(quitMeetBar),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        menu.delegate = self
        contextMenu = menu
        return menu
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === contextMenu else { return }
        statusItem?.button?.highlight(false)
        contextMenu = nil
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.highlight(false)
    }

    @objc private func openMeetBar() {
        guard let button = statusItem?.button else { return }
        DispatchQueue.main.async { [weak self, weak button] in
            guard let self, let button else { return }
            self.showPopover(from: button)
        }
    }

    @objc private func copyLastMeetingLink() {
        guard let url = model.mostRecentMeetingURL else { return }
        model.copy(url)
    }

    @objc private func openSettings() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.activate(ignoringOtherApps: true)
            if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: self) {
                _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: self)
            }
        }
    }

    @objc private func quitMeetBar() {
        NSApp.terminate(nil)
    }

    private func showPreviewWindow() {
        let content = MeetBarPopover()
            .environmentObject(model)
        let controller = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: controller)
        window.title = "MeetBar Preview"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        previewWindow = window
    }
}

private final class StatusItemInteractionView: NSView {
    var onLeftClick: (() -> Void)?
    var contextMenuProvider: (() -> NSMenu?)?

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
        } else {
            onLeftClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = contextMenuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
