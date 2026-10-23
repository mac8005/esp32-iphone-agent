import Foundation
import Network
import UIKit

/// What the agent and the pointer need from the screen (VideoFeed, or a fake in tests). Port of screen.py.
@MainActor protocol ScreenSource: AnyObject {
    var live: Bool { get }
    var frame: Data? { get }
    var updated: Double { get }
    var capturedAt: Double { get }
    var aspect: Double { get }
    /// After a gesture that ended at `since`: wait until the screen shows its result (and fetch it, in snap mode).
    func afterAction(since: Double) async
    func prepareFrame(after: Double) async throws
}

/// How a run gets its frames: the live stream (`stream on`, the default: a frame in under a second), or one
/// snap after each action (`stream off`; waits for the board's whole GOP, often 20-30 s).
enum FrameMode: String {
    case stream, snap
    static let key = "frameModeV2"  // V2: drops the old saved "snap" left by earlier automatic fallbacks
    /// Temporary override, cleared when the next run starts.
    static var fallback: FrameMode?
    static var current: FrameMode {
        get { fallback ?? FrameMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .stream }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key); fallback = nil }
    }
}

extension ScreenSource {
    func prepareFrame(after: Double) async throws {
        guard live, frame != nil else { throw BlindError() }
        if capturedAt > 0 && (capturedAt < after || now() - capturedAt > 5) {
            throw BlindError(reason: "The mirrored screen is delayed. No action was sent.")
        }
    }

    func afterAction(since: Double) async { await settled() }

    /// Wait until the screen stops changing (AirPlay only sends frames on change). Mid-animation frames are big and
    /// can reach us late over BLE, so a gap is only "quiet" once it also covers the last frame's transport lag.
    func settled(quiet: Double = 0.5, least: Double = 0.3, most: Double = 4) async {
        let started = now()
        try? await Task.sleep(nanoseconds: UInt64(least * 1e9))
        while now() - updated < quiet + lag && now() - started < most {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// How late the shown frame arrived after the board got it (0 when unknown), capped.
    private var lag: Double { capturedAt > 0 ? min(max(updated - capturedAt, 0), 1) : 0 }

    /// The first frame captured after `since` (received, when capture times are unknown), or nil if none in time.
    func fresh(since: Double, timeout: Double = 0.8) async -> Data? {
        let deadline = now() + timeout
        while (capturedAt > 0 ? capturedAt : updated) <= since {
            if Task.isCancelled || now() > deadline { return nil }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return frame
    }
}

/// The phone's screen, mirrored over AirPlay to the board and forwarded over BLE, as JPEG frames.
@MainActor final class VideoFeed: ObservableObject, ScreenSource {
    @Published private(set) var frame: Data?
    @Published private(set) var size = CGSize.zero
    @Published private(set) var note = ""  // last decoder problem, shown in Diagnostics
    private(set) var updated = 0.0
    /// When the board received the shown frame, in local time (≈; see `boardClock`).
    private(set) var capturedAt = 0.0
    /// A decode error or a lost chunk since the last good frame: the shown frame is stale until the next IDR.
    private(set) var broken = false
    private var clockOffset: Double?  // local s − board s, the smallest seen (≈ the link latency)
    var mirroring = false  // board status says ap == streaming
    var metrics: Metrics?
    weak var device: HIDDevice?

    private var assembler = VideoAssembler()
    private let decoder = H264Decoder()
    private var generation: UInt64 = 0

    init() {
        decoder.onFrame = { [weak self] f in DispatchQueue.main.async { self?.publish(f) } }
        decoder.onError = { [weak self] msg in
            DispatchQueue.main.async {
                let bg = UIApplication.shared.applicationState == .background
                self?.note = bg ? "\(msg) [in background]" : msg
                self?.metrics?.decodeError(background: bg)
                self?.broken = true
            }
        }
    }

    var live: Bool { mirroring && frame != nil && !broken && (device?.connected ?? false) }

    /// Frame width / height (portrait iPhone as a fallback).
    var aspect: Double { size.width > 0 && size.height > 0 ? size.width / size.height : 9 / 19.5 }

    /// One `video` notify from BoardLink.
    func receive(_ chunk: Data) {
        metrics?.videoBytes(chunk.count)
        let dropsBefore = assembler.drops
        let unit = assembler.add(chunk)
        if assembler.drops > dropsBefore {
            metrics?.videoDrops(assembler.drops - dropsBefore)
            resetDecoder(clearConfiguration: false)
        }
        guard let unit else { return }
        if !unit.snap { boardClock(ms: Int(unit.boardMs)) }  // snap units are resent late: their ages say nothing
        if unit.idr { metrics?.idrSeen() }
        decoder.queue.async { [decoder] in decoder.decode(unit) }
    }

    /// The link (re)connected: chunk numbering starts over.
    func resetStream() {
        assembler.reset()
        clockOffset = nil
        frame = nil
        updated = 0
        capturedAt = 0
        resetDecoder()
    }

    private func resetDecoder(clearConfiguration: Bool = true) {
        generation &+= 1
        broken = true
        decoder.queue.async { [decoder] in decoder.reset(clearConfiguration: clearConfiguration) }
    }

    /// A board timestamp (status `up`, or a streamed unit) just arrived: keep the smallest offset.
    func boardClock(ms: Int) {
        let offset = now() - Double(ms) / 1000
        clockOffset = min(clockOffset ?? offset, offset)
    }

    /// Show a still frame (demo data).
    func show(_ jpeg: Data, width: Int, height: Int, boardMs: UInt32 = 0) {
        publish(H264Decoder.Frame(jpeg: jpeg, width: width, height: height, decodeMs: 4.2,
                                  unit: AccessUnit(data: Data(), idr: false, config: false, snap: false, boardMs: boardMs),
                                  generation: generation))
    }

    private func publish(_ f: H264Decoder.Frame) {
        guard f.generation == generation else { return }
        let capture = clockOffset.map { Double(f.unit.boardMs) / 1000 + $0 } ?? now()
        guard capture >= capturedAt else { return }  // replay must not move the visible screen backwards
        frame = f.jpeg
        updated = now()
        capturedAt = capture
        broken = false
        if size.width != CGFloat(f.width) || size.height != CGFloat(f.height) {
            size = CGSize(width: f.width, height: f.height)
        }
        metrics?.frameDecoded(ms: f.decodeMs)
    }

    /// The app asked the board to forward the stream (`stream on`).
    private(set) var streamOn = false

    /// Seconds a snap may take: the buffered GOP over the measured BLE rate, doubled, at least 8 s.
    var snapTimeout: Double {
        let gopBytes = Double(metrics?.board?.gop ?? 0)
        let kbps = max(metrics?.bleKbps ?? 0, metrics?.board?.ble?.kbps ?? 0, 40)
        return min(30, max(8, gopBytes * 8 / 1000 / kbps * 2 + 3))
    }

    /// Streaming never requests a second copy of the buffered GOP. A delayed frame must catch up
    /// within a bounded wait; arrival time is not evidence that its contents are current. A screen
    /// transition can queue tens of seconds of video on the board's BLE link: while newer frames keep
    /// arriving, the wait is extended (up to `catchUp` in total) instead of giving up mid-drain.
    @discardableResult
    func currentFrame(maxAge: Double = 5, wait: Double = 15, catchUp: Double = 90, after: Double = 0) async throws -> String {
        if streamOn {
            let started = now()
            var deadline = started + wait, seen = capturedAt
            while true {
                try Task.checkCancellation()
                if live && capturedAt >= after && now() - capturedAt <= maxAge { return "live" }
                if capturedAt > seen {
                    seen = capturedAt
                    deadline = min(max(deadline, now() + wait), started + catchUp)
                }
                if now() >= deadline {
                    throw BlindError(reason: "The mirrored screen is delayed or cannot be decoded. No action was sent.")
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        try await snap()
        guard live, capturedAt >= after, now() - capturedAt <= maxAge else {
            throw BlindError(reason: "The snapshot is out of date. No action was sent.")
        }
        return "snap"
    }

    func prepareFrame(after: Double) async throws {
        try await currentFrame(after: after)
    }

    /// Ask the board for the current GOP and wait until it is decoded. Returns the latency in ms.
    @discardableResult
    func snap(timeout: Double? = nil) async throws -> Double {
        guard let device else { throw DeviceError(message: "board not connected") }
        guard !streamOn else { throw DeviceError(message: "Stop video streaming before requesting a snapshot") }
        resetDecoder()
        let started = now()
        if let channel = device as? CommandChannel {
            try await channel.send("snap", timeout: min(timeout ?? snapTimeout, 30))
        } else {
            try await device.send("snap")
        }
        await withCheckedContinuation { c in decoder.queue.async { c.resume() } }  // the GOP is decoded
        try? await Task.sleep(nanoseconds: 30_000_000)  // let the last frame reach the main queue
        let ms = (now() - started) * 1000
        metrics?.snapLatency(ms)
        return ms
    }

    func stream(_ on: Bool) async throws {
        try await device?.send("stream \(on ? "on" : "off")")
        streamOn = on
    }

    /// Wait for the result of a gesture, never interpret an old frame as an unchanged screen.
    func afterAction(since: Double) async {
        do {
            try await currentFrame(after: since)
        } catch {
            note = error.localizedDescription
            broken = true
            DebugLog.write("frame after action failed: \(error.localizedDescription)")
        }
    }

    /// The link dropped: the board forgets `stream on`.
    func linkLost() { streamOn = false; resetStream() }
}

/// Video over the board's Wi-Fi (TCP): the phone is on the board's hotspot for AirPlay anyway, and this is
/// ~20-50x faster than BLE notifies. Same chunks as `video`, each after a u16 LE length (docs/ble-protocol.md).
/// While it is up the board sends video only here; when it drops, the board falls back to BLE.
@MainActor final class VideoSocket {
    var onChunk: ((Data) -> Void)?
    private(set) var up = false
    private var connection: NWConnection?
    var connecting: Bool { connection != nil && !up }

    func connect(host: String, port: UInt16, token: String) {
        close()
        guard let port = NWEndpoint.Port(rawValue: port) else { return }
        let c = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        connection = c
        c.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, self.connection === c else { return }
                switch state {
                case .ready:
                    self.up = true
                    DebugLog.write("video: Wi-Fi link up (\(host))")
                case .failed(let error), .waiting(let error):  // waiting: e.g. Local Network access denied
                    self.closed("\(error)")
                default: break
                }
            }
        }
        c.send(content: Data((token + "\n").utf8), completion: .idempotent)
        c.start(queue: .main)
        read(c)
    }

    func close() {
        connection?.cancel()
        connection = nil
        up = false
    }

    private func closed(_ why: String) {
        DebugLog.write("video: Wi-Fi link down: \(why)")
        close()
    }

    private func read(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 2, maximumLength: 2) { [weak self] head, _, _, error in
            MainActor.assumeIsolated {
                guard let self, self.connection === c else { return }
                guard let head, head.count == 2, error == nil else { return self.closed(error.map { "\($0)" } ?? "closed by board") }
                let n = Int(head[head.startIndex]) | Int(head[head.startIndex + 1]) << 8
                c.receive(minimumIncompleteLength: n, maximumLength: n) { [weak self] body, _, _, error in
                    MainActor.assumeIsolated {
                        guard let self, self.connection === c else { return }
                        guard let body, body.count == n, error == nil else { return self.closed(error.map { "\($0)" } ?? "closed by board") }
                        self.onChunk?(Data(body))
                        self.read(c)
                    }
                }
            }
        }
    }
}
