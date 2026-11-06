import SwiftUI

/// Instellingen: vergrendeling, uitloggen, overal uitloggen, versie en links.
struct SettingsView: View {
    /// Mac: in het eigen Instellingen-venster (⌘,)
    var inSettingsWindow = false
    @EnvironmentObject private var session: Session
    @State private var confirmLogout = false
    @State private var confirmLogoutAll = false
    @State private var busyAll = false
    @State private var error: String?

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return String(format: L("%@ (build %@)"), v, b)
    }

    var body: some View {
        Form {
            if let error {
                Section {
                    Text(error).foregroundStyle(BeheerTheme.bad)
                }
            }

            Section {
                Toggle(isOn: Binding(
                    get: { session.lockEnabled },
                    set: { on in Task { await session.setLockEnabled(on) } }
                )) {
                    Label(String(format: L("Vergrendelen met %@"), session.biometryName), systemImage: session.biometryIcon)
                }
                .disabled(!session.canLock && !session.lockEnabled)
            } header: {
                Text(L("Beveiliging"))
            } footer: {
                Text(session.canLock
                     ? L("Bij het starten en na 5 minuten op de achtergrond vraagt de app om te ontgrendelen.")
                     : L("Stel eerst een toegangscode of wachtwoord in op dit apparaat."))
            }

            if session.isSignedIn {
                Section {
                    Button {
                        confirmLogout = true
                    } label: {
                        Label(L("Uitloggen"), systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    Button(role: .destructive) {
                        confirmLogoutAll = true
                    } label: {
                        HStack {
                            Label(L("Overal uitloggen"), systemImage: "rectangle.portrait.and.arrow.right.fill")
                            if busyAll {
                                Spacer()
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(busyAll)
                } header: {
                    Text(L("Account"))
                } footer: {
                    Text(L("Overal uitloggen laat alle sessies vervallen: deze app, andere apparaten en het web-dashboard."))
                }
            }

            Section {
                Link(destination: Config.website) {
                    Label("tunr.online", systemImage: "globe")
                }
                Link(destination: Config.webPlayer) {
                    Label(L("Webspeler"), systemImage: "play.circle")
                }
                Link(destination: Config.beheerSite) {
                    Label("beheer.tunr.online", systemImage: "safari")
                }
            } header: {
                Text(L("Links"))
            }

            Section {
                LabeledContent(L("Versie"), value: version)
                LabeledContent(L("Bundle-id"), value: Bundle.main.bundleIdentifier ?? "nl.lrvdlinden.tunr.beheer")
            } header: {
                Text(L("Over"))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle(L("Instellingen"))
        .largeTitle()
        .confirmationDialog(L("Uitloggen?"), isPresented: $confirmLogout, titleVisibility: .visible) {
            Button(L("Uitloggen"), role: .destructive) { session.logout() }
            Button(L("Annuleren"), role: .cancel) {}
        }
        .confirmationDialog(L("Overal uitloggen?"), isPresented: $confirmLogoutAll, titleVisibility: .visible) {
            Button(L("Overal uitloggen"), role: .destructive) {
                Task { await logoutAll() }
            }
            Button(L("Annuleren"), role: .cancel) {}
        } message: {
            Text(L("Alle sessies van het beheer (deze app, andere apparaten en het web-dashboard) vervallen meteen."))
        }
    }

    private func logoutAll() async {
        busyAll = true
        defer { busyAll = false }
        do {
            try await session.logoutAll()
            error = nil
        } catch {
            if error is CancellationError { return }
            if let e = error as? APIError, e.isUnauthorized {
                session.logout(L("Je sessie is verlopen. Log opnieuw in."))
                return
            }
            self.error = (error as? APIError)?.errorDescription ?? L("Er ging iets mis.")
        }
    }
}
