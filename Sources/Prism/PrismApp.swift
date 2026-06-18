import SwiftUI

@main
struct PrismApp: App {
    @StateObject private var browser = BrowserState()
    @StateObject private var ai = AIController()

    var body: some Scene {
        WindowGroup("Prism") {
            ContentView()
                .environmentObject(browser)
                .environmentObject(ai)
                .frame(minWidth: 1100, minHeight: 720)
                .background(Theme.deepSpace)
                .preferredColorScheme(.dark)
                .onAppear {
                    // Give the AI controller a handle to the browser so the
                    // agent loop can actually drive navigation.
                    ai.attach(browser: browser)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
