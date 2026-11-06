import SwiftUI

struct LoginView: View {
    @Environment(Session.self) private var session
    @State private var user = "LRvdLinden"
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?
    private enum Field { case user, password }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.17, green: 0.18, blue: 0.21), Theme.dark], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            RadialGradient(colors: [Theme.red.opacity(0.45), .clear], center: .top, startRadius: 10, endRadius: 420)
                .ignoresSafeArea()
            VStack(spacing: 22) {
                Image("BrandMark")
                    .resizable()
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                VStack(spacing: 6) {
                    Text("A-Alerts").font(.largeTitle.weight(.heavy)).foregroundStyle(.white)
                    Text("Beheer van A-Alerts (P2000 Apeldoorn)").foregroundStyle(.white.opacity(0.7))
                }
                VStack(spacing: 12) {
                    TextField("Gebruikersnaam", text: $user)
                        .textContentType(.username)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .focused($focus, equals: .user)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    SecureField("Wachtwoord", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(login)
                }
                .textFieldStyle(LoginFieldStyle())
                if let error {
                    Text(error).font(.callout).foregroundStyle(Color(red: 1, green: 0.55, blue: 0.55)).multilineTextAlignment(.center)
                }
                Button(action: login) {
                    HStack {
                        if busy { ProgressView().tint(.white) }
                        Text("Inloggen").fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.red, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(busy || user.isEmpty || password.count < 6)
                .opacity(user.isEmpty || password.count < 6 ? 0.6 : 1)
            }
            .padding(28)
            .frame(maxWidth: 400)
        }
        .onAppear { focus = .password }
    }

    private func login() {
        guard !busy, password.count >= 6 else { return }
        busy = true
        error = nil
        Task {
            do { try await session.login(user: user.trimmingCharacters(in: .whitespaces), password: password) }
            catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

private struct LoginFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(14)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.15)))
            .foregroundStyle(.white)
    }
}
