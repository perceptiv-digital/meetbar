import AppKit
import SwiftUI

@main
struct MeetBarApp: App {
    @NSApplicationDelegateAdaptor(MeetBarAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @State private var showsMenuBarItem = !ProcessInfo.processInfo.arguments.contains("--preview-window")

    var body: some Scene {
        MenuBarExtra(isInserted: $showsMenuBarItem) {
            MeetBarPopover()
                .environmentObject(model)
        } label: {
            MeetBarMenuBarMark()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

@MainActor
final class MeetBarAppDelegate: NSObject, NSApplicationDelegate {
    private var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.arguments.contains("--preview-window") else { return }

        let model = AppModel()
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
