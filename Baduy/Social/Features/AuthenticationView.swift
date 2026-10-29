import SwiftUI
import AuthenticationServices

struct AuthenticationView: View {
    @ObservedObject var state: AppState
    @ViewState private var registering = false
    @ViewState private var username = ""
    @ViewState private var email = ""
    @ViewState private var password = ""
    @ViewState private var confirm = ""
    @ViewState private var nonce: String?
    @ViewState private var recovering = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "leaf.circle").font(.largeTitle).foregroundStyle(.green)
                        Text("Explore with respect").font(.title2.bold())
                        Text("Share experiences, discover guides, and connect around Kanekes.").foregroundStyle(.secondary)
                    }.padding(.vertical)
                }
                Section {
                    TextField("Username", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if registering {
                        TextField("Recovery email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    SecureField("Password", text: $password).textContentType(registering ? .newPassword : .password)
                    if registering { SecureField("Confirm password", text: $confirm).textContentType(.newPassword) }
                    Button(registering ? "Create account" : "Sign in") {
                        Task {
                            if registering { await state.signup(username: username, email: email, password: password) }
                            else { await state.login(username: username, password: password) }
                            password = ""; confirm = ""
                        }
                    }.disabled(state.busy || !valid)
                } header: { Text(registering ? "Create your account" : "Welcome back") } footer: {
                    if registering { Text("Use 3–24 letters, numbers, or underscores for your username and at least 12 characters for your password.") }
                }
                Section {
                    if (Bundle.main.object(forInfoDictionaryKey: "APPLE_SIGN_IN_ENABLED") as? String) == "YES" {
                    SignInWithAppleButton(.signIn) { request in
                        do {
                            let value = try SecureStore.nonce(); nonce = value
                            request.nonce = SecureStore.hash(value); request.requestedScopes = [.fullName, .email]
                        } catch { state.error = error.localizedDescription }
                    } onCompletion: { result in
                        let value = nonce; nonce = nil
                        Task { await state.apple(result, nonce: value) }
                    }.frame(height: 48).disabled(state.busy)
                    }
                    Button(registering ? "Already have an account? Sign in" : "New here? Create an account") { registering.toggle() }
                    if !registering { Button("Forgot password?") { recovering = true } }
                }
                if state.busy { ProgressView("Please wait…") }
            }.navigationTitle("Kanekes")
            .sheet(isPresented: $recovering) { RecoveryView(app: state) }
        }
    }
    private var valid: Bool {
        AppState.validUsername(username) && !password.isEmpty && (!registering || (password.count >= 12 && password == confirm && email.contains("@")))
    }
}
struct ChooseUsernameView: View {
    @ObservedObject var state: AppState
    @ViewState private var username = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Choose a public username") {
                    TextField("Username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("3–24 letters, numbers, or underscores. Your email remains private.").font(.footnote)
                    Button("Continue") { Task { await state.chooseUsername(username) } }.disabled(!AppState.validUsername(username) || state.busy)
                }
                Button("Sign out", role: .destructive) { Task { await state.logout() } }
            }.navigationTitle("Your profile")
        }
    }
}
