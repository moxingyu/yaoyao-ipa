import SwiftUI

@main
struct YaoyaoApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear { store.bootstrap() }
        }
    }
}
