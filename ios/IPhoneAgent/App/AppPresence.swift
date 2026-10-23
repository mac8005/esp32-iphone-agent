import Foundation
import UIKit

/// The agent works on the phone this app runs on, so the app must be out of the way: Start sends it to the
/// Home Screen (and checks that iOS really put it in the background), and a run holds while it is in front.
extension AppModel {

    private var inBackground: Bool { UIApplication.shared.applicationState == .background }

    /// Leaves our own app without touching the screen: the board's Cmd+H, then its home flick as a fallback.
    /// The model is never asked to do this.
    func leaveApp() async -> Bool {
        for method in ["cmd+h", "home swipe"] {
            if inBackground { return true }
            do {
                switch method {
                case "cmd+h": try await pointer.key("cmd+h")
                default: try await pointer.goHome()
                }
            } catch {
                DebugLog.write("leave app: \(method) failed: \(error.localizedDescription)")
                continue
            }
            if await waitForBackground(2) { DebugLog.write("leave app: in background after \(method)"); return true }
            DebugLog.write("leave app: still in front after \(method)")
        }
        return false
    }

    /// After a run that ended in another app: bring this one back by searching for it, since iOS lets no app
    /// bring itself to the front. Search opens with Cmd+Space, or else from the Home Screen with a pull-down.
    /// Gives up quietly; the Live Activity still shows the result.
    func returnToApp() async {
        guard inBackground, board.connected, !MockMode.on else { return }
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "ESP32 Agent"
        for method in ["cmd+space", "home pull-down"] {
            do {
                if method == "cmd+space" {
                    try await pointer.key("cmd+space")
                } else {
                    _ = try? await pointer.key("esc")  // close a half-open Search from the first try
                    try await pointer.goHome()
                    try await Task.sleep(nanoseconds: 600_000_000)
                    try await pointer.swipe(0.5, 0.35, 0.5, 0.6, hold: false)
                }
                try await Task.sleep(nanoseconds: 700_000_000)
                try await pointer.type(name)
                try await Task.sleep(nanoseconds: 900_000_000)
                try await pointer.key("enter")
            } catch {
                DebugLog.write("return to app: \(method) failed: \(error.localizedDescription)")
                continue
            }
            for _ in 0..<30 where UIApplication.shared.applicationState != .active {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if UIApplication.shared.applicationState == .active { return DebugLog.write("return to app: in front after \(method)") }
            DebugLog.write("return to app: still in background after \(method)")
        }
    }

    /// Neither way worked: ask the user to swipe up, and wait for it (bounded).
    func askUserToLeave() async -> Bool {
        homeHint = String(localized: "Swipe up to go to the Home Screen, and I'll start.")
        defer { homeHint = nil }
        return await waitForBackground(30)
    }

    /// Before each look and gesture of a run. If the agent itself brought the app to the front (it tapped our
    /// Live Activity, a notification or an intent), or Continue was just tapped here, send the app away at once;
    /// if the user opened it, wait until they leave. The model never sees or taps this app's own screens.
    func holdWhileInFront() async throws {
        guard UIApplication.shared.applicationState == .active, agent.running, !MockMode.on else { return }
        let ours = now() - agent.lastActed < 3 || now() - resumeAsked < 5
        DebugLog.write("run: ESP32 Agent is in front (\(ours ? "after an agent action" : "opened by the user")); holding")
        let since = now()
        var away = false
        if ours { away = await leaveApp() }
        if !away {
            homeHint = String(localized: "Paused while you're here. Go to the Home Screen and I'll go on.")
            live.show(.pausedInApp, mood: .thinking)
            defer { homeHint = nil }
            while !inBackground {
                try Task.checkCancellation()
                if !feed.live {
                    _ = try await agent.waitForScreen()
                    live.show(.pausedInApp, mood: .thinking)
                }
                try await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        _ = await feed.fresh(since: since, timeout: 3)  // a frame of the screen that is in front now
        await feed.settled()
        DebugLog.write("run: app in background again, going on")
    }

    private func waitForBackground(_ seconds: Double) async -> Bool {
        let deadline = now() + seconds
        while !inBackground {
            if now() > deadline { return false }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return true
    }
}
