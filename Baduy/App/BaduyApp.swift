import SwiftUI

@main struct BaduyApp: App {
    @StateObject private var state = AppState()
    var body: some Scene {
        WindowGroup {
            RootView(state: state).task { await state.restore() }
        }
    }
}
struct RootView: View {
    @ObservedObject var state: AppState
    var body: some View {
        Group {
            if state.restoring { ProgressView("Restoring session…") }
            else if state.recoveryReady { NewPasswordView(app: state) }
            else if !state.signedIn { AuthenticationView(state: state) }
            else if state.profile?.username == nil { ChooseUsernameView(state: state) }
            else { MainTabs(state: state) }
        }
        .onOpenURL { url in Task { await state.handleEmailLink(url) } }
        .alert("Something needs attention", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
            Button("OK") { state.error = nil }
        } message: { Text(state.error ?? "") }
        .alert("Account", isPresented: Binding(get: { state.notice != nil }, set: { if !$0 { state.notice = nil } })) {
            Button("OK") { state.notice = nil }
        } message: { Text(state.notice ?? "") }
    }
}
struct MainTabs: View {
    @ObservedObject var state: AppState
    @SceneStorage("selectedTab") private var selected = 0
    var body: some View {
        TabView(selection: $selected) {
            Tab("Home", systemImage: "house", value: 0) { HomeView(app: state, active: selected == 0) }
            Tab("Guide", systemImage: "person.text.rectangle", value: 1) { GuideListView(repository: state.repository) }
            Tab("Map", systemImage: "map", value: 2) { LocationRoutedMapView(app: state, isActive: selected == 2) }
        }
    }
}
