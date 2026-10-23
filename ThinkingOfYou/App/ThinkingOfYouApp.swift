//  ThinkingOfYouApp.swift
//  ThinkingOfYou/App — entry point: builds the environment, wires nudge taps
//  and scene-phase changes. The UI starts at RootView (ThinkingOfYou/UI).

import SwiftUI

@main
@MainActor
struct ThinkingOfYouApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .task {
                    let environment = env
                    appDelegate.nudgeHandler = { route in environment.handleNudge(route) }
                    await environment.launch()
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    env.scenePhaseChanged(phase)
                }
        }
    }
}
