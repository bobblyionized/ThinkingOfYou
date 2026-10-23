//  AppDelegate.swift
//  ThinkingOfYou/App — notification delegate. Turns a tapped nudge into a
//  NudgeRoute and hands it to the environment, buffering routes that arrive
//  before the SwiftUI scene has wired `nudgeHandler` (cold launch from a tap).

import UIKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private var pendingRoutes: [NudgeRoute] = []

    /// Set by ThinkingOfYouApp once the environment exists; flushes buffered routes.
    var nudgeHandler: (@MainActor (NudgeRoute) -> Void)? {
        didSet { flushPendingRoutes() }
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    private func route(_ route: NudgeRoute) {
        if let nudgeHandler {
            nudgeHandler(route)
        } else {
            pendingRoutes.append(route)
        }
    }

    private func flushPendingRoutes() {
        guard let nudgeHandler, !pendingRoutes.isEmpty else { return }
        let routes = pendingRoutes
        pendingRoutes.removeAll()
        for route in routes { nudgeHandler(route) }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let nudge = NudgeScheduler.route(from: response.notification.request.content.userInfo)
        if let nudge {
            Task { @MainActor in
                self.route(nudge)
            }
        }
        completionHandler()
    }
}
