import Combine
import SwiftUI

@MainActor final class RecoveryState: ObservableObject {
    @Published var sent = false
    @Published var busy = false
    @Published var error: String?
    let app: AppState
    init(app: AppState) { self.app = app }
    func send(_ email: String) async {
        busy = true; error = nil; defer { busy = false }
        do {
            let flow = PendingEmailFlow(verifier: try SecureStore.nonce(), email: email.trimmingCharacters(in: .whitespacesAndNewlines), kind: .recovery, createdAt: Date())
            try SecureStore.saveFlow(flow)
            _ = try await app.api.request("auth/v1/recover?redirect_to=baduy%3A%2F%2Fauth%2Frecovery", method: "POST", body: ["email": flow.email, "code_challenge": SecureStore.challenge(flow.verifier), "code_challenge_method": "s256"], authenticated: false)
            sent = true
        } catch { self.error = error.localizedDescription }
    }
}
struct RecoveryView: View {
    @StateObject private var state: RecoveryState
    @ViewState private var email = ""
    init(app: AppState) { _state = StateObject(wrappedValue: RecoveryState(app: app)) }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Recovery email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(state.sent)
                if state.sent {
                    Text("If this address has an account, a recovery link has been sent. Open it on this device to choose a new password in Kanekes.")
                    Text("If testing in Simulator, open the email link inside Simulator.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Button("Send recovery link") { Task { await state.send(email) } }.disabled(state.busy || !email.contains("@"))
                }
                if state.busy { ProgressView() }
                if let error = state.error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Recover account").toolbar { CloseButton() }
        }
    }
}
struct NewPasswordView: View {
    @ObservedObject var app: AppState
    @ViewState private var password = ""
    @ViewState private var confirmation = ""
    var body: some View {
        NavigationStack {
            Form {
                SecureField("New password", text: $password).textContentType(.newPassword)
                SecureField("Confirm password", text: $confirmation).textContentType(.newPassword)
                Text("Use at least 12 characters.").font(.footnote)
                Button("Update password") { Task { await app.updateRecoveredPassword(password) } }
                    .disabled(app.busy || password.count < 12 || password != confirmation)
                Button("Cancel recovery") { Task { await app.logout() } }.disabled(app.busy)
                if app.busy { ProgressView() }
            }.navigationTitle("Choose a new password")
        }
    }
}
