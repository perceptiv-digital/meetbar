import AppKit
import SwiftUI

@main
struct MeetBarApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MeetBarPopover()
                .environmentObject(model)
        } label: {
            Image(systemName: "video.badge.plus")
                .accessibilityLabel("MeetBar")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
