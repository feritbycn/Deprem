import SwiftUI
import UserNotifications

@main
struct DepremKalkaniApp: App {
    @Environment(\.scenePhase) private var phase
    @StateObject private var store = QuakeStore.shared

    init() {
        UNUserNotificationCenter.current().delegate = NotifDelegate.shared
        BG.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onAppear { Notifier.requestPermission() }
        }
        .onChange(of: phase) { newPhase in
            if newPhase == .background { BG.schedule() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: QuakeStore

    var body: some View {
        TabView {
            QuakeListView()
                .tabItem { Label("Depremler", systemImage: "waveform.path.ecg") }
            MapTab()
                .tabItem { Label("Harita", systemImage: "map") }
            EmergencyView()
                .tabItem { Label("Acil", systemImage: "exclamationmark.triangle.fill") }
            GuideView()
                .tabItem { Label("Rehber", systemImage: "book") }
            SettingsView()
                .tabItem { Label("Ayarlar", systemImage: "gearshape") }
        }
        .task {
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }
}
