import XCTest
@testable import IPhoneAgent

/// Port of server/tests/test_agent.py.
@MainActor final class AgentTests: XCTestCase {
    func testStaleFrameNeverReachesTheModel() async {
        let model = FakeModel { _ in "1. Tap Search" }
        let screen = FakeScreen()
        screen.capturedAt = now() - 180
        screen.updated = now()
        let agent = AgentLoop(phone: nil, screen: screen, actor: model, planner: model, trace: nil)
        do { try await agent.replan(); XCTFail("Expected stale screen rejection") }
        catch { XCTAssertTrue(error is BlindError) }
        XCTAssertTrue(model.prompts.isEmpty)
    }

    func testPlannerTimeoutRetriesOnceAndChecksGateAgain() async throws {
        let model = TimeoutModel(failures: 1)
        let agent = AgentLoop(phone: nil, screen: FakeScreen(), actor: model, planner: model, trace: nil)
        var gates = 0
        var retryShown = false
        agent.gate = { gates += 1 }
        agent.onDoing = { if case .retrying = $0 { retryShown = true } }
        try await agent.replan()
        XCTAssertEqual(model.calls, 2)
        XCTAssertEqual(gates, 4)
        XCTAssertTrue(retryShown)
        XCTAssertEqual(agent.plan, "1. Observe the screen")
    }

    func testPlannerTimeoutStopsAfterOneRetry() async {
        let model = TimeoutModel(failures: 10)
        let agent = AgentLoop(phone: nil, screen: FakeScreen(), actor: model, planner: model, trace: nil)
        do { try await agent.replan(); XCTFail("Expected timeout") }
        catch { XCTAssertTrue(ModelRequestFailure.isTimeout(error)) }
        XCTAssertEqual(model.calls, 2)
        XCTAssertTrue(agent.steps.isEmpty)
    }

    func testPlannerAndActorHaveDistinctPendingAndReceivingStates() async throws {
        let model = ProgressModel()
        let agent = AgentLoop(phone: nil, screen: FakeScreen(), actor: model, planner: model, trace: nil)
        var states: [String] = []
        agent.onDoing = {
            switch $0 {
            case .waiting: states.append("waiting")
            case .planning: states.append("planning")
            case .thinking: states.append("thinking")
            default: break
            }
        }
        try await agent.replan()
        XCTAssertEqual(states.last, "planning")
        XCTAssertEqual(states.first, "waiting")
        XCTAssertNil(model.onProgress)
        states = []
        _ = try await agent.nextActions()
        XCTAssertEqual(states.first, "waiting")
        XCTAssertEqual(states.last, "thinking")
        XCTAssertFalse(states.contains("planning"))
        XCTAssertNil(model.onProgress)
    }

    func testParseSingleAction() throws {
        let acts = try Actions.parseActions("THINK: The Search pill is visible, so I tap it.\nDO: tap 500 814")
        XCTAssertEqual(acts, [["thought": .str("The Search pill is visible, so I tap it."), "thought_zh": .str(""),
                               "action": .str("tap"), "x": .int(500), "y": .int(814)]])
        XCTAssertEqual(acts[0].keys, ["thought", "thought_zh", "action", "x", "y"])
    }

    func testParseSeveralActionsKeepsThoughtOnFirst() throws {
        let acts = try Actions.parseActions("THINK: Type and search.\nDO: type Whiteboard\nDO: key enter")
        XCTAssertEqual(acts.map { $0["action"]?.str }, ["type", "key"])
        XCTAssertEqual(acts[0]["text"], .str("Whiteboard"))
        XCTAssertEqual(acts[1]["combo"], .str("enter"))
        XCTAssertNil(acts[1]["thought"])
    }

    func testParseCapsAtSixActions() throws {
        let reply = "THINK: draw\n" + (0..<10).map { "DO: tap \($0) \($0)" }.joined(separator: "\n")
        XCTAssertEqual(try Actions.parseActions(reply).count, 6)
    }

    func testParsePathAndCircle() throws {
        XCTAssertEqual(try Actions.parseCommand("path 100 200 300 400 500 600")["points"],
                       .arr([.arr([.int(100), .int(200)]), .arr([.int(300), .int(400)]), .arr([.int(500), .int(600)])]))
        XCTAssertEqual(try Actions.parseCommand("circle 500 450 200"),
                       ["action": .str("circle"), "x": .int(500), "y": .int(450), "r": .int(200)])
    }

    func testParseRejectsBadCommands() {
        for line in ["fly 1 2", "tap 500", "path 1 2 3"] {
            XCTAssertThrowsError(try Actions.parseCommand(line), line)
        }
    }

    func testParseRequiresADoLine() {
        XCTAssertThrowsError(try Actions.parseActions("THINK: I am not sure what to do."))
    }

    func testParsePlanWithAndWithoutLanguages() {
        XCTAssertTrue(Actions.parsePlan("EN:\n1. Tap Search\nZH:\n1. 点搜索") == ("1. Tap Search", "1. 点搜索"))
        XCTAssertTrue(Actions.parsePlan("1. Tap Search") == ("1. Tap Search", "1. Tap Search"))
    }

    func testCircleIsClosedAndRoundOnATallScreen() {
        let aspect = 0.46  // width / height of a portrait iPhone frame
        let pts = circle(0.5, 0.5, 0.2, aspect: aspect)
        XCTAssertEqual(pts[0].x, pts.last!.x, accuracy: 1e-9)
        XCTAssertEqual(pts[0].y, pts.last!.y, accuracy: 1e-9)
        for p in pts {  // equal radius in pixels: y offsets shrink by the aspect ratio
            XCTAssertEqual(hypot(p.x - 0.5, (p.y - 0.5) / aspect), 0.2, accuracy: 1e-9)
        }
    }

    func testActorMayNotRepeatAMoveThatChangedNothing() async throws {
        let actor = FakeModel { n in
            n == 1 ? "THINK: again\nDO: swipe 382 253 382 150" : "THINK: other\nDO: tap 1 2"
        }
        let agent = AgentLoop(phone: nil, screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        agent.steps = [["action": .str("swipe"), "x1": .int(382), "y1": .int(253), "x2": .int(382), "y2": .int(150),
                        "changed": .bool(false)]]
        let acts = try await agent.nextActions()
        XCTAssertEqual(acts[0].act["action"], .str("tap"))
        XCTAssertTrue(actor.prompts[1].contains("changed nothing"))
    }

    func testConfidentDecisionTapsTheChosenTextWithoutTheActor() async throws {
        let actor = FakeModel { _ in "THINK: slow\nDO: tap 1 2" }
        let decider = FakeDecider(("t1", 0.97))
        let agent = AgentLoop(phone: nil, screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        agent.decider = decider
        agent.findSpots = { _ in [TextSpot(text: "Search", x: 0.5, y: 0.82), TextSpot(text: "Notes — Open", x: 0.3, y: 0.21)] }
        let acts = try await agent.nextActions()
        XCTAssertEqual(acts[0].act["action"], .str("tap"))
        XCTAssertEqual(acts[0].act["x"]?.double, 300)
        XCTAssertEqual(acts[0].act["y"]?.double, 210)
        XCTAssertTrue(actor.prompts.isEmpty)
        XCTAssertEqual(decider.choices.last?.value, "other")
    }

    func testUnsureOrFailedDecisionFallsBackToTheActor() async throws {
        let actor = FakeModel { _ in "THINK: look\nDO: tap 1 2" }
        let agent = AgentLoop(phone: nil, screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        agent.findSpots = { _ in [TextSpot(text: "Search", x: 0.5, y: 0.82)] }
        agent.decider = FakeDecider(("t0", 0.48))
        _ = try await agent.nextActions()
        XCTAssertEqual(actor.prompts.count, 1)
        agent.decider = FakeDecider(("other", 0.99))
        _ = try await agent.nextActions()
        XCTAssertEqual(actor.prompts.count, 2)
        agent.decider = FakeDecider(nil)  // e.g. no access to the endpoint
        _ = try await agent.nextActions()
        XCTAssertEqual(actor.prompts.count, 3)
        XCTAssertNil(agent.decider)  // not asked again this run
    }

    func testDecisionRequestAndAnswerFormat() throws {
        let body = DecisionClient.body(context: "Goal: x", image: Data([1, 2]), question: "Which?",
                                       choices: [(value: "t0", description: "Tap A"), (value: "other", description: "None")])
        XCTAssertEqual(body["model"] as? String, "gpt-6-luna")
        let q = (body["questions"] as? [[String: Any]])?.first
        XCTAssertEqual(q?["type"] as? String, "choice")
        XCTAssertEqual((q?["choices"] as? [[String: String]])?.map { $0["value"] }, ["t0", "other"])
        let reply = #"{"answers":[{"type":"choice","name":"next","choice":"t0","confidence":0.99,"probabilities":[]}]}"#
        let answer = try DecisionClient.answer(Data(reply.utf8))
        XCTAssertEqual(answer.value, "t0")
        XCTAssertEqual(answer.confidence, 0.99)
        XCTAssertNil(DecisionClient(baseURL: "https://openrouter.ai/api/v1", apiKey: "k"))
        XCTAssertEqual(DecisionClient(baseURL: "https://api.openai.com/v1/", apiKey: "k")?.url.absoluteString,
                       "https://api.openai.com/v1/decisions")
    }

    func testRepeatingAMoveThatKeepsChangingTheScreenIsNotStuck() {
        let agent = AgentLoop(phone: nil, screen: nil, actor: nil, planner: nil, trace: nil)
        let swipe: JObject = ["action": .str("swipe"), "x1": .int(500), "y1": .int(800), "x2": .int(500), "y2": .int(400)]
        agent.steps = [swipe.merging(["changed": .bool(true)]), swipe.merging(["changed": .bool(true)])]
        XCTAssertFalse(agent.repeating(swipe))
        agent.steps[1]["changed"] = .bool(false)  // reached the end of the list
        XCTAssertTrue(agent.repeating(swipe))
    }

    func testPreciseTapFlag() throws {
        XCTAssertEqual(try Actions.parseCommand("tap 120 640 precise"),
                       ["action": .str("tap"), "x": .int(120), "y": .int(640), "precise": .bool(true)])
        XCTAssertNil(try Actions.parseCommand("tap 120 640")["precise"])
    }

    // MARK: - beyond the Python tests

    func testHistoryIsFormattedLikePythonJSONDumps() async throws {
        let actor = FakeModel { _ in "THINK: ok\nDO: wait" }
        let agent = AgentLoop(phone: nil, screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        agent.steps = [
            ["t": .num(1), "shot": .bool(true), "action": .str("plan"), "plan": .str("1. x")],
            ["t": .num(2), "shot": .bool(true), "thought": .str("hi"), "action": .str("tap"), "x": .int(1), "y": .int(2),
             "think_s": .num(1.5), "changed": .bool(true)],
            ["t": .num(3), "shot": .bool(false), "action": .str("type"), "text": .str("café")],
        ]
        _ = try await agent.nextActions()
        XCTAssertTrue(actor.prompts[0].hasSuffix(
            "Recent actions:\n{\"action\": \"tap\", \"x\": 1, \"y\": 2} -> screen changed\n"
            + "{\"action\": \"type\", \"text\": \"caf\\u00e9\"}\n\nNext action?"))
    }

    func testPromptsAreVerbatimFromThePythonServer() throws {
        let agentPy = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../server/hidagent/agent.py").standardized
        guard let source = try? String(contentsOf: agentPy, encoding: .utf8) else {
            throw XCTSkip("server source not reachable from the test runner")
        }
        XCTAssertTrue(source.contains("PLANNER_PROMPT = \"\"\"" + Prompts.planner + "\"\"\""))
        XCTAssertTrue(source.contains("ACTOR_PROMPT = \"\"\"" + Prompts.actorServer + "\"\"\""))
    }

    func testRunStopsAfterThreeErrorsInARow() async {
        let model = FakeModel { n in n == 1 ? "1. do it" : "no action here" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: model, planner: model, trace: nil)
        await agent.run()
        XCTAssertEqual(agent.steps.last?["action"], .str("fail"))
        XCTAssertEqual(agent.steps.last?["reason"], .str("3 errors in a row"))
    }

    func testRunFinishesOnDone() async {
        let model = FakeModel { n in n == 1 ? "1. go home" : n == 2 ? "THINK: home\nDO: home" : "THINK: there\nDO: done ok" }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: model, planner: model, trace: nil)
        await agent.run()
        XCTAssertEqual(phone.calls, ["home"])
        XCTAssertEqual(agent.steps.map { $0["action"]?.str }, ["plan", "home", "done"])
        XCTAssertEqual(agent.steps.last?["answer"], .str("ok"))
    }
}

// MARK: - fakes

@MainActor final class FakeModel: ChatModel {
    let model = "fake"
    private(set) var prompts: [String] = []
    private let reply: (Int) -> String

    init(_ reply: @escaping (Int) -> String) { self.reply = reply }

    func chat(system: String, text: String, image: Data?, maxTokens: Int, temperature: Double) async throws -> ChatResult {
        prompts.append(text)
        return ChatResult(text: reply(prompts.count), firstToken: nil, total: 0)
    }
}

@MainActor final class FakeDecider: DecisionModel {
    let answer: (String, Double)?
    private(set) var choices: [(value: String, description: String)] = []
    init(_ answer: (String, Double)?) { self.answer = answer }
    func choose(context: String, image: Data, question: String,
                choices: [(value: String, description: String)]) async throws -> (value: String, confidence: Double) {
        self.choices = choices
        guard let answer else { throw LLMError(message: "HTTP 404") }
        return answer
    }
}

@MainActor final class FakeScreen: ScreenSource {
    var live = true
    var frame: Data? = Data([0xff, 0xd8])
    var updated = 0.0
    var capturedAt = 0.0
    var aspect = 0.46
}

@MainActor final class FakeDevice: HIDDevice {
    var links = 1
    var connected = true
    var sent: [String] = []
    func send(_ command: String) async throws -> String { sent.append(command); return "" }
    func waitConnected(_ timeout: TimeInterval) async -> Bool { connected }
}

@MainActor final class FakeGestures: Gestures {
    let device: HIDDevice = FakeDevice()
    var calls: [String] = []
    func tap(_ x: Double, _ y: Double, aim: Bool) async throws { calls.append("tap") }
    func swipe(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, hold: Bool) async throws { calls.append("swipe") }
    func drag(_ points: [CGPoint], hold: Bool) async throws { calls.append("drag") }
    func type(_ text: String) async throws { calls.append("type") }
    func key(_ combo: String) async throws { calls.append("key") }
    func goHome() async throws { calls.append("home") }
    func goBack() async throws { calls.append("back") }
    func reset() async throws { calls.append("reset") }
}

@MainActor private final class TimeoutModel: ChatModel {
    let model = "timeout-test"
    let failures: Int
    var calls = 0
    init(failures: Int) { self.failures = failures }
    func chat(system: String, text: String, image: Data?, maxTokens: Int, temperature: Double) async throws -> ChatResult {
        calls += 1
        if calls <= failures { throw URLError(.timedOut) }
        return ChatResult(text: "1. Observe the screen", total: 0)
    }
}

@MainActor private final class ProgressModel: ChatModel, ModelProgressReporting {
    let model = "progress-test"
    var onProgress: ((ModelResponseProgress) -> Void)?
    func chat(system: String, text: String, image: Data?, maxTokens: Int, temperature: Double) async throws -> ChatResult {
        onProgress?(.waiting)
        onProgress?(.receiving)
        return ChatResult(text: "THINK: Wait for the screen\nDO: wait", total: 0)
    }
}
