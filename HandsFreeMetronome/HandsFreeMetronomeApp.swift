import SwiftUI
import TipKit
import LeeoKit

@main
struct HandsFreeMetronomeApp: App {
    init() {
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault)
        ])
        LeeoEngagement.shared.registerLaunch()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .leeoSatisfactionCheck(HandsFreeMetronomeSpec.self)
        }
    }
}
