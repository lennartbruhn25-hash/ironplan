import SwiftUI

@main
struct IronplanApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await model.appBecameActive() }
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Heute", systemImage: "sun.max.fill") }
            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
            HubView()
                .tabItem { Label("Aktivitäten", systemImage: "heart.text.square.fill") }
            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape.fill") }
        }
        .tint(.orange)
        .task { await model.bootstrap() }
    }
}
