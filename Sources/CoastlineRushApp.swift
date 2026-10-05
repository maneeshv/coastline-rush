import SwiftUI

@main
struct CoastlineRushApp: App {
    @StateObject private var controller = GameController()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some Scene {
        #if os(macOS)
        Window("Coastline Rush", id: "game") {
            game.frame(minWidth: 720, minHeight: 650)
        }
        .defaultSize(width: 1100, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Run") {
                Button("Start a run") { controller.start() }.keyboardShortcut("r", modifiers: .command)
                Button("Pause / resume") { controller.togglePause() }.keyboardShortcut("p", modifiers: .command)
                Button("How to play") { controller.showPanel(.help) }
            }
        }
        #else
        WindowGroup { game.statusBarHidden() }
        #endif
    }

    private var game: some View {
        GameRootView(controller: controller)
            .preferredColorScheme(.dark)
            .onAppear { controller.setSystemReducedMotion(accessibilityReduceMotion) }
            .onChange(of: accessibilityReduceMotion) { controller.setSystemReducedMotion($0) }
            .onChange(of: scenePhase) { phase in
                controller.setActive(phase == .active)
            }
    }
}
