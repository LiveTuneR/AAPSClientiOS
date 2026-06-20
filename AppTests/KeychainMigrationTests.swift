import XCTest
@testable import AAPSClientiOS

final class KeychainMigrationTests: XCTestCase {
    private func uniqueService() -> String { "test.kc.\(UUID().uuidString)" }

    func test_migration_copiesValuesAndIsIdempotent() throws {
        let service = uniqueService()
        let source = KeychainStore(service: service)
        try source.set("https://ns.example/", for: .nsUrl)
        try source.set("token-123", for: .nsAccessToken)

        try source.migrate(to: source)
        XCTAssertEqual(try source.get(.nsUrl), "https://ns.example/")
        XCTAssertEqual(try source.get(.nsAccessToken), "token-123")

        let empty = KeychainStore(service: uniqueService())
        XCTAssertNoThrow(try empty.migrate(to: empty))

        try source.delete(.nsUrl)
        try source.delete(.nsAccessToken)
    }
}
