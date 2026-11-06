import SwiftUI

/// Inloggen bij een webbeheer met dezelfde gebruikersnaam en hetzelfde wachtwoord als beheer.html (.htaccess).
struct SiteLoginView<Logo: View>: View {
    let title: LocalizedStringKey
    let site: String
    let account: SiteAccount
    let onSignedIn: () -> Void
    @ViewBuilder var logo: () -> Logo

    @State private var user = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?
    private enum Field { case user, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                logo()
                    .frame(width: 84, height: 84)
                    .padding(.top, 40)
                VStack(spacing: 6) {
                    Text(title).font(Theme.display(.title2))
                    Text(verbatim: site).font(.subheadline).foregroundStyle(.secondary)
                }
                VStack(spacing: 12) {
                    TextField("Gebruikersnaam", text: $user)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .user)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    SecureField("Wachtwoord", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(signIn)
                }
                .textFieldStyle(.roundedBorder)
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.bad)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(action: signIn) {
                    HStack {
                        if busy { ProgressView().tint(.white) }
                        Text("Inloggen").bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || user.isEmpty || password.isEmpty)
                Text("Dezelfde inlog als de beheerpagina op de website. Wordt alleen op dit apparaat bewaard, in de sleutelhanger.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .sensoryFeedback(.error, trigger: error)
    }

    private func signIn() {
        guard !busy, !user.isEmpty, !password.isEmpty else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await account.signIn(user: user.trimmingCharacters(in: .whitespaces), password: password)
                password = ""
                onSignedIn()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Gekleurde melding boven het beheer (zoals .result good/warn/bad in beheer.html).
struct ResultBanner: View {
    let kind: LRvdLindenStore.Banner.Kind
    let text: String
    var onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onClose) { Image(systemName: "xmark").font(.caption.bold()) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Sluiten")
        }
        .padding(12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(color.opacity(0.35)))
    }

    private var color: Color {
        switch kind {
        case .good: Theme.good
        case .warn: Theme.build
        case .bad: Theme.bad
        }
    }

    private var icon: String {
        switch kind {
        case .good: "checkmark.circle.fill"
        case .warn: "clock.fill"
        case .bad: "exclamationmark.triangle.fill"
        }
    }
}

/// Korte melding onderaan (toast in beheer.html).
struct ToastOverlay: ViewModifier {
    @Binding var text: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let t = text {
                Text(t)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.thickMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: t) {
                        try? await Task.sleep(for: .seconds(2.4))
                        withAnimation { if text == t { text = nil } }
                    }
            }
        }
        .animation(.easeOut(duration: 0.2), value: text)
    }
}

extension View {
    func toast(_ text: Binding<String?>) -> some View { modifier(ToastOverlay(text: text)) }
}
