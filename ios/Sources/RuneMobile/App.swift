import SwiftUI

@main
struct RuneMobileApp: App {
    @StateObject private var store = MobileStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            BrowserScreen(store: store)
                .tint(RuneTheme.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { store.persist() }
        }
    }
}
