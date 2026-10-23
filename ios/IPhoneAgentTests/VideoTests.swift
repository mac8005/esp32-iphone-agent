import Network
import XCTest
@testable import IPhoneAgent

/// `video` chunk reassembly (docs/ble-protocol.md).
final class VideoTests: XCTestCase {
    typealias F = VideoAssembler.Flags

    func chunk(_ seq: UInt16, _ flags: F, _ payload: [UInt8], ms: UInt32? = nil) -> Data {
        var d = Data([UInt8(seq & 0xff), UInt8(seq >> 8), flags.rawValue])
        if let ms { d.append(contentsOf: [UInt8(ms & 0xff), UInt8(ms >> 8 & 0xff), UInt8(ms >> 16 & 0xff), UInt8(ms >> 24)]) }
        d.append(contentsOf: payload)
        return d
    }

    let sps: [UInt8] = [0, 0, 0, 1, 0x67, 1, 2]
    let idr: [UInt8] = [0, 0, 0, 1, 0x65, 9, 9]
    let p: [UInt8] = [0, 0, 0, 1, 0x41, 7]

    /// 2026-10-23 phone log: BLE chunks arriving after the switch to Wi-Fi counted ~65k drops and stalled video.
    @MainActor func testLateChunksFromTheOtherPathAreIgnored() {
        let feed = VideoFeed()
        let metrics = Metrics()
        feed.metrics = metrics
        feed.receive(chunk(10, [.start, .config], sps, ms: 1))
        feed.overWiFi = true
        feed.receive(chunk(11, [.start, .end], p, ms: 2))  // late BLE leftover
        feed.receive(chunk(9000, [.start, .end, .config], sps, ms: 3), wifi: true)  // the board restarts there
        feed.receive(chunk(9001, [.start, .end, .idr], idr, ms: 4), wifi: true)
        XCTAssertEqual(metrics.drops, 0)
        XCTAssertFalse(feed.broken)
    }

    func testInOrderChunksMakeAccessUnits() {
        var a = VideoAssembler()
        XCTAssertEqual(a.add(chunk(0, [.start, .end, .config], sps, ms: 1000))?.config, true)
        XCTAssertNil(a.add(chunk(1, [.start, .idr], Array(idr[0..<5]), ms: 1001)))
        let unit = a.add(chunk(2, [.end, .idr], Array(idr[5...])))
        XCTAssertEqual(unit, AccessUnit(data: Data(idr), idr: true, config: false, snap: false, boardMs: 1001))
        XCTAssertEqual(a.add(chunk(3, [.start, .end], p, ms: 1200))?.data, Data(p))
        XCTAssertEqual(a.drops, 0)
    }

    func testGapDropsUntilTheNextKeyUnit() {
        var a = VideoAssembler()
        _ = a.add(chunk(10, [.start, .end, .idr], idr, ms: 1))
        XCTAssertNil(a.add(chunk(11, [.start], p, ms: 2)))
        XCTAssertNil(a.add(chunk(13, [.end], p)))           // 12 lost: the half unit is dropped
        XCTAssertEqual(a.drops, 1)
        XCTAssertNil(a.add(chunk(14, [.start, .end], p, ms: 3)))  // a P-frame after a gap is useless
        XCTAssertNotNil(a.add(chunk(15, [.start, .end, .config], sps, ms: 4)))  // configuration does not replace the missing reference frame
        XCTAssertNil(a.add(chunk(16, [.start, .end], p, ms: 5)))
        XCTAssertNotNil(a.add(chunk(17, [.start, .end, .idr], idr, ms: 6)))
        XCTAssertNotNil(a.add(chunk(18, [.start, .end], p, ms: 7)))
    }

    func testRecoversOnIDRAndWrapsSeq() {
        var a = VideoAssembler()
        _ = a.add(chunk(65534, [.start, .end, .idr], idr, ms: 1))
        XCTAssertNotNil(a.add(chunk(65535, [.start, .end], p, ms: 2)))
        XCTAssertNotNil(a.add(chunk(0, [.start, .end], p, ms: 3)))  // u16 wrap is not a gap
        XCTAssertEqual(a.drops, 0)
        XCTAssertNil(a.add(chunk(5, [.start, .end], p, ms: 4)))
        XCTAssertEqual(a.drops, 4)
        let unit = a.add(chunk(6, [.start, .end, .idr, .snap], idr, ms: 5))
        XCTAssertEqual(unit?.snap, true)
    }

    func testWaitsForAKeyUnitAtStartAndIgnoresBench() {
        var a = VideoAssembler()
        XCTAssertNil(a.add(chunk(0, [.start, .end], p, ms: 1)))
        XCTAssertNil(a.add(chunk(1, [.bench], [UInt8](repeating: 0, count: 100))))
        XCTAssertEqual(a.benchBytes, 103)
        XCTAssertNotNil(a.add(chunk(2, [.start, .end, .idr], idr, ms: 2)))
    }

    func testAnnexBSplitsNALUnits() {
        let units = annexBUnits(Data(sps + [0, 0, 1, 0x68, 5] + idr))
        XCTAssertEqual(units.map { $0.first! & 0x1f }, [7, 8, 5])
        XCTAssertEqual(units[0], Data([0x67, 1, 2]))
    }
}

@MainActor final class VideoFreshnessTests: XCTestCase {
    func testRecentlyReceivedOldFrameIsNotCurrentAndDoesNotTriggerSnapshot() async throws {
        let feed = VideoFeed()
        let device = FakeDevice()
        feed.device = device
        feed.mirroring = true
        feed.boardClock(ms: 180_000)
        feed.show(Data([1]), width: 480, height: 1040)
        try await feed.stream(true)
        do {
            try await feed.currentFrame(wait: 0)
            XCTFail("A newly received three-minute-old frame must not be used")
        } catch { XCTAssertTrue(error is BlindError) }
        XCTAssertEqual(device.sent, ["stream on"])
    }

    func testDelayedStreamThatKeepsCatchingUpIsWaitedFor() async throws {
        let feed = VideoFeed()
        let device = FakeDevice()
        feed.device = device
        feed.mirroring = true
        feed.boardClock(ms: 100_000)
        feed.show(Data([1]), width: 480, height: 1040, boardMs: 80_000)  // 20 s behind, like a draining burst
        try await feed.stream(true)
        Task { @MainActor in
            try await Task.sleep(nanoseconds: 200_000_000)
            feed.show(Data([2]), width: 480, height: 1040, boardMs: 90_000)
            try await Task.sleep(nanoseconds: 200_000_000)
            feed.show(Data([3]), width: 480, height: 1040, boardMs: 100_000)
        }
        let source = try await feed.currentFrame(wait: 0.3, catchUp: 5)
        XCTAssertEqual(source, "live")
        XCTAssertEqual(feed.frame, Data([3]))
    }

    /// A local stand-in for the board's TCP video server: checks the token line, then sends framed chunks.
    func testWiFiVideoSendsTokenAndDeliversFramedChunks() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        var token = ""
        listener.newConnectionHandler = { c in
            c.start(queue: .main)
            c.receive(minimumIncompleteLength: 1, maximumLength: 64) { data, _, _, _ in
                token = String(decoding: data ?? Data(), as: UTF8.self)
                var out = Data()
                for chunk in [Data([1, 0, 3, 9]), Data(repeating: 7, count: 1400)] {
                    out.append(contentsOf: [UInt8(chunk.count & 0xff), UInt8(chunk.count >> 8)])
                    out.append(chunk)
                }
                c.send(content: out, completion: .idempotent)
            }
        }
        let ready = expectation(description: "listening")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.start(queue: .main)
        await fulfillment(of: [ready], timeout: 5)
        defer { listener.cancel() }

        let socket = VideoSocket()
        var chunks: [Data] = []
        let got = expectation(description: "two chunks")
        socket.onChunk = { chunks.append($0); if chunks.count == 2 { got.fulfill() } }
        socket.connect(host: "127.0.0.1", port: listener.port!.rawValue, token: "abc123")
        await fulfillment(of: [got], timeout: 5)
        XCTAssertEqual(token, "abc123\n")
        XCTAssertEqual(chunks, [Data([1, 0, 3, 9]), Data(repeating: 7, count: 1400)])
        XCTAssertTrue(socket.up)
        socket.close()
    }

    func testReconnectClearsThePreviousPhonesFrame() {
        let feed = VideoFeed()
        let device = FakeDevice()
        feed.device = device
        feed.mirroring = true
        feed.show(Data([1]), width: 480, height: 1040)
        feed.resetStream()
        XCTAssertNil(feed.frame)
        XCTAssertFalse(feed.live)
    }
}
