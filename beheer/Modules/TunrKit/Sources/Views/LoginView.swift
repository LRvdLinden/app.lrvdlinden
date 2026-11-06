import SwiftUI

/// Inloggen met gebruikersnaam en wachtwoord (actie `login`).
struct LoginView: View {
    @EnvironmentObject private var session: Session
    @State private var user = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case user, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 48)
                BeheerLogo(size: 38)
                VStack(alignment: .leading, spacing: 16) {
                    Text(L("Inloggen"))
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    if let msg = error ?? session.loginMessage {
                        NoticeBanner(text: msg, bad: error != nil)
                    }
                    field(L("Gebruikersnaam")) {
                        userField
                    }
                    field(L("Wachtwoord")) {
                        passwordField
                    }
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().controlSize(.small).tint(.white) }
                            Text(L("Inloggen"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.accent)
                    .disabled(busy || user.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
                .card(padding: 20)
                .frame(maxWidth: 420)
                Text(L("Alleen voor de beheerder van Tunr."))
                    .font(.caption)
                    .foregroundStyle(BeheerTheme.dim)
            }
            .padding(BeheerTheme.edge)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .onAppear { focus = .user }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(BeheerTheme.secondary)
            content()
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(BeheerTheme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(BeheerTheme.stroke, lineWidth: 1)
                }
        }
    }

    @ViewBuilder private var userField: some View {
        #if os(iOS)
        TextField("", text: $user)
            .textContentType(.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .focused($focus, equals: .user)
            .onSubmit { focus = .password }
        #else
        TextField("", text: $user)
            .autocorrectionDisabled()
            .focused($focus, equals: .user)
            .onSubmit { focus = .password }
        #endif
    }

    @ViewBuilder private var passwordField: some View {
        #if os(iOS)
        SecureField("", text: $password)
            .textContentType(.password)
            .submitLabel(.go)
            .focused($focus, equals: .password)
            .onSubmit { Task { await submit() } }
        #else
        SecureField("", text: $password)
            .focused($focus, equals: .password)
            .onSubmit { Task { await submit() } }
        #endif
    }

    private func submit() async {
        let u = user.trimmingCharacters(in: .whitespaces)
        guard !busy, !u.isEmpty, !password.isEmpty else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await session.login(user: u, password: password)
            password = ""
        } catch let e as APIError {
            // 401 bij inloggen = verkeerde gegevens
            if e.status == 401 || e.code == "unauthorized" {
                error = L("Onjuiste gebruikersnaam of wachtwoord.")
            } else {
                error = e.errorDescription
            }
        } catch {
            if error is CancellationError { return }
            self.error = L("Geen verbinding met de server.")
        }
    }
}
