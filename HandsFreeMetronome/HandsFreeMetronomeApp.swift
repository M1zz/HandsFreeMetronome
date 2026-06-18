import SwiftUI
import TipKit

@main
struct HandsFreeMetronomeApp: App {
    init() {
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault)
        ])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
