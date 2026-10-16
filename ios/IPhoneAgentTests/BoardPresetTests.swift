import CryptoKit
import XCTest
@testable import IPhoneAgent

final class BoardPresetTests: XCTestCase {
    @MainActor func testBoardPresetAuthenticatesAndScopesCredential() throws {
        let original = Keychain.get("llm-api-key") ?? ""
        defer { Keychain.set(original, for: "llm-api-key") }
        Keychain.set("", for: "llm-api-key")
        let suite = "board-preset-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let bytes = Data(repeating: 42, count: 32)
        let key = "sk-test-credential-for-provisioning-only"
        let sealed = try AES.GCM.seal(Data(key.utf8), using: SymmetricKey(data: bytes)).combined!
        let settings = Settings(defaults: defaults, info: [
            "IAPresetBaseURL": "https://api.openai.com/v1",
            "IAPresetWrappingKey": bytes.base64EncodedString()
        ])
        var tampered = sealed
        tampered[tampered.count - 1] ^= 1
        XCTAssertFalse(settings.importBoardPreset(tampered.base64EncodedString()))
        XCTAssertFalse(settings.importBoardPreset("invalid"))
        settings.baseURL = "https://example.com/v1"
        XCTAssertFalse(settings.importBoardPreset(sealed.base64EncodedString()))
        settings.baseURL = "https://api.openai.com/v1"
        XCTAssertTrue(settings.importBoardPreset(sealed.base64EncodedString()))
        XCTAssertEqual(Keychain.get("llm-api-key"), key)
        settings.apiKey = "existing-user-key"
        XCTAssertFalse(settings.importBoardPreset(sealed.base64EncodedString()))
        XCTAssertEqual(settings.apiKey, "existing-user-key")
    }
}
