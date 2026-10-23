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

    /// After a run that ended in another app: bring this one back, since iOS lets no app bring itself to the
    /// front. Built from steps runs do reliably: the board's Home key, a tap on the Home Screen's Search field
    /// (found by text recognition; else the pull-down), this app's name, then its result (else Return). Each
    /// look is logged and saved to Documents/return/ for the log export.
    func returnToApp() async {
        guard inBackground, board.connected, pointer.calibrated, !MockMode.on else { return }
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "ESP32 Agent"
        do {
            try await pointer.goHome()
            try await Task.sleep(nanoseconds: 600_000_000)
            let home = await look("home")
            if let search = home.first(where: { s in s.y > 0.5 && ["search", "suchen"].contains { s.text.lowercased().contains($0) } }) {
                try await pointer.tap(search.x, search.y)
            } else {
                try await pointer.swipe(0.5, 0.35, 0.5, 0.6, hold: false)  // pull down on the Home Screen
            }
            try await Task.sleep(nanoseconds: 800_000_000)
            try await pointer.key("cmd+a")  // replace an earlier query
            try await pointer.type(name)
            try await Task.sleep(nanoseconds: 1_200_000_000)
            // the query itself shows the name too: the app's result is the top-most match
            let hits = await look("results").filter { $0.text.lowercased().hasPrefix(name.lowercased()) }.sorted { $0.y < $1.y }
            if hits.count > 1, let top = hits.first {
                try await pointer.tap(top.x, top.y)
            } else {
                try await pointer.key("enter")  // opens the top hit
            }
        } catch {
            return DebugLog.write("return to app: \(error.localizedDescription)")
        }
        // inactive = iOS is bringing the app forward; it becomes active a moment later
        for _ in 0..<50 where inBackground { try? await Task.sleep(nanoseconds: 100_000_000) }
        if inBackground { _ = await look("failed") }
        DebugLog.write("return to app: \(inBackground ? "still in background" : "in front")")
    }

    /// A fresh frame's texts for returnToApp, logged, with the frame kept in Documents/return/.
    private func look(_ stage: String) async -> [TextSpot] {
        _ = try? await feed.currentFrame(wait: 3, catchUp: 5, after: now() - 0.1)
        guard let frame = feed.frame else {
            DebugLog.write("return to app: \(stage): no screen")
            return []
        }
        let dir = DebugLog.url.deletingLastPathComponent().appendingPathComponent("return")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? frame.write(to: dir.appendingPathComponent("\(stage).jpg"))
        let spots = await TextSpots.find(frame)
        DebugLog.write("return to app: \(stage): " + spots.prefix(14).map { String(format: "%@ (%.2f, %.2f)", $0.text, $0.x, $0.y) }.joined(separator: ", "))
        return spots
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
