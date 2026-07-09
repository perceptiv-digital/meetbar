import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Google API") {
                HStack {
                    Image(systemName: model.hasOAuthConfiguration ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.hasOAuthConfiguration ? .green : .orange)
                    Text(model.hasOAuthConfiguration ? "OAuth desktop client configured" : "OAuth desktop client required")
                    Spacer()
                    Button(model.hasOAuthConfiguration ? "Replace…" : "Import…") {
                        model.importOAuthConfiguration()
                    }
                }
                Text("Create a Desktop OAuth client in Google Cloud, enable the Google Meet REST API, then import the downloaded JSON file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Google Accounts") {
                if model.accounts.isEmpty {
                    Text("No accounts connected.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.accounts) { account in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(account.displayName)
                                Text(account.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove", role: .destructive) {
                                model.removeAccount(account)
                            }
                        }
                    }
                }

                Button("Add Google Account") {
                    Task { await model.addGoogleAccount() }
                }
                .disabled(!model.hasOAuthConfiguration || model.isWorking)
            }

            Section("Privacy") {
                Text("OAuth tokens stay in your macOS Keychain. MeetBar requests only identity details and permission to create meeting spaces. Meeting links and labels stay on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 430)
        .navigationTitle("MeetBar Settings")
    }
}
