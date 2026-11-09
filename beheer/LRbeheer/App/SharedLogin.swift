import BingrKit
import Observation
import P2000Kit
import PasrKit
import SwiftUI
import TunrKit

/// Eén beheer-inlog voor alle omgevingen.
///
/// Op de servers staan dezelfde gebruikersnaam en hetzelfde wachtwoord voor elke beheeromgeving (bron:
/// BEHEER_APP_USER / BEHEER_APP_PASSWORD in LRvdLinden/app.lrvdlinden.secrets, verdeeld door de workflow
/// beheer-login-sync; zie server/README.md). LRbeheer vraagt ze één keer, bewaart ze alleen op dit apparaat in de
/// sleutelhanger, en logt daarmee in bij elke omgeving via de eigen, ongewijzigde inlog van die omgeving. Verloopt een
/// sessie (bv. het token van 12 uur), dan logt LRbeheer stil opnieuw in zodra je de omgeving opent.
@MainActor
@Observable
final class SharedLogin {
    static let shared = SharedLogin()

    struct Credentials: Codable { let user: String; let password: String }

    enum Outcome: Equatable { case busy, ok, failed(String) }

    private(set) var user: String?
    private(set) var results: [BeheerEnvironment: Outcome] = [:]
    private(set) var busy = false
    var showSheet = false

    private static let account = "beheer.shared"

    var hasCredentials: Bool { user != nil }

    private init() {
        user = Keychain.readCodable(Self.account, as: Credentials.self)?.user
    }

    private var credentials: Credentials? { Keychain.readCodable(Self.account, as: Credentials.self) }

    /// Inloggen bij alle omgevingen; bewaart de inlog als minstens één omgeving hem accepteert.
    func signInAll(user: String, password: String) async {
        busy = true
        defer { busy = false }
        let u = user.trimmingCharacters(in: .whitespaces)
        for env in BeheerEnvironment.allCases { results[env] = .busy }
        for env in BeheerEnvironment.allCases {
            results[env] = await Self.login(env, u, password)
        }
        if results.values.contains(.ok) {
            Keychain.writeCodable(Self.account, Credentials(user: u, password: password))
            self.user = u
            CentralPush.shared.sync(force: true)
        }
    }

    /// Stil inloggen bij omgevingen die (nog of weer) niet ingelogd zijn. Fouten blijven stil; de omgeving toont dan
    /// gewoon zijn eigen inlogscherm.
    func autoSignIn(_ envs: [BeheerEnvironment] = BeheerEnvironment.allCases) async {
        guard let c = credentials, !busy else { return }
        for env in envs where !env.isSignedIn {
            results[env] = await Self.login(env, c.user, c.password)
        }
    }

    func forget() {
        Keychain.delete(Self.account)
        user = nil
        results = [:]
    }

    private static func login(_ env: BeheerEnvironment, _ user: String, _ password: String) async -> Outcome {
        do {
            switch env {
            case .lrvdlinden: try await LRvdLindenStore.shared.account.signIn(user: user, password: password)
                Task { await LRvdLindenStore.shared.load() }
            case .pixelforges: try await PixelForgesStore.shared.account.signIn(user: user, password: password)
                Task { await PixelForgesStore.shared.load() }
            case .bingr: try await BingrEnvironment.login(user: user, password: password)
            case .tunr: try await TunrEnvironment.login(user: user, password: password)
            case .pasr: try await PasrEnvironment.login(user: user, password: password)
            case .p2000: try await P2000Environment.login(user: user, password: password)
            case .bekendr: try await BekendrStore.shared.signIn(user: user, password: password)
                Task { await BekendrStore.shared.load() }
            }
            return .ok
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

/// Blad "Eén inlog voor alle omgevingen" (overzicht).
struct SharedLoginView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SharedLoginForm()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } } }
        }
    }
}

/// Het formulier zelf (ook in Instellingen).
struct SharedLoginForm: View {
    @State private var login = SharedLogin.shared
    @State private var user = ""
    @State private var password = ""

    var body: some View {
            Form {
                Section {
                    TextField("Gebruikersnaam", text: $user)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Wachtwoord", text: $password)
                        .textContentType(.password)
                    Button {
                        Task { await login.signInAll(user: user, password: password); password = "" }
                    } label: {
                        HStack {
                            if login.busy { ProgressView() }
                            Text("Inloggen bij alle omgevingen").bold()
                        }
                    }
                    .disabled(login.busy || user.isEmpty || password.isEmpty)
                } footer: {
                    Text("Dezelfde beheer-inlog voor alle omgevingen. Alleen op dit apparaat bewaard, in de sleutelhanger; LRbeheer logt er stil mee opnieuw in als een sessie verloopt.")
                }
                if !login.results.isEmpty {
                    Section("Resultaat") {
                        ForEach(BeheerEnvironment.allCases) { env in
                            HStack(spacing: 12) {
                                EnvironmentIcon(env: env, size: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: env.name)
                                    if case let .failed(m) = login.results[env] {
                                        Text(m).font(.caption).foregroundStyle(Theme.bad)
                                    }
                                }
                                Spacer()
                                switch login.results[env] {
                                case .busy: ProgressView()
                                case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                                case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.bad)
                                case nil: EmptyView()
                                }
                            }
                        }
                    }
                }
                if login.hasCredentials {
                    Section {
                        LabeledContent("Bewaard", value: login.user ?? "")
                        Button("Beheer-inlog vergeten", role: .destructive) { login.forget() }
                    }
                }
            }
            .navigationTitle("Eén inlog")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if user.isEmpty { user = login.user ?? "" } }
            .sensoryFeedback(.success, trigger: login.results.values.filter { $0 == .ok }.count)
    }
}
