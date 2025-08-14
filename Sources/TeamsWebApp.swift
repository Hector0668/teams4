import SwiftUI

@main
struct TeamsWebApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        NotificationPresenter.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView().ignoresSafeArea()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                BackgroundAudio.shared.stop()
            case .background:
                BackgroundAudio.shared.start()
            default:
                break
            }
        }
    }
}