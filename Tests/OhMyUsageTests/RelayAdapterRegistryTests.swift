import XCTest
@testable import OhMyUsage

final class RelayAdapterRegistryTests: XCTestCase {
    func testBundledManifestsIncludeRelayAdapterResources() {
        let ids = Set(RelayAdapterRegistry.shared.builtInManifests().map(\.id))

        XCTAssertTrue(ids.contains("generic-newapi"))
        XCTAssertTrue(ids.contains("xiaomimimo-token-plan"))
        XCTAssertTrue(ids.contains("moonshot"))
    }

    func testBundledManifestsAreUniqueByID() {
        let ids = RelayAdapterRegistry.shared.builtInManifests().map(\.id)

        XCTAssertEqual(ids.count, Set(ids).count)
    }
}
