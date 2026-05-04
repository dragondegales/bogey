import SwiftUI

@main
struct GolfWatchApp: App {
    @StateObject private var roundStore = RoundStore()
    @StateObject private var locationManager = LocationManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(roundStore)
                .environmentObject(locationManager)
                .task {
                    roundStore.bootstrapIfNeeded()
                    locationManager.requestAuthorizationIfNeeded()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        locationManager.requestAuthorizationIfNeeded()
                        locationManager.startIfAuthorized()
                    case .inactive, .background:
                        locationManager.stopUpdating()
                    @unknown default:
                        break
                    }
                }
        }
    }
}
