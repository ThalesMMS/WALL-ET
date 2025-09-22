import XCTest
@testable import WALL_ET

final class ElectrumTransactionsAdapterTests: XCTestCase {
    func testRefineOrderWithPositionsPreservesConfirmedHeightOrdering() async throws {
        let adapter = ElectrumTransactionsAdapter()

        let ids = ["tx1", "tx2", "tx3", "tx4", "tx5"]
        let heights: [String: Int?] = [
            "tx1": 120,
            "tx2": 121,
            "tx3": 120,
            "tx4": nil,
            "tx5": 121
        ]

        var posCache: [String: Int] = [:]
        posCache["120|tx1"] = 5
        posCache["120|tx3"] = 2
        posCache["121|tx2"] = 1
        posCache["121|tx5"] = 7

        adapter.debugSetHeightMap(heights)
        adapter.debugSetPosCache(posCache)

        let refined = try await adapter.debugRefineOrder(ids: ids)

        XCTAssertEqual(refined, ["tx4", "tx3", "tx1", "tx2", "tx5"])
    }

    func testRefineOrderWithPositionsDeduplicatesHeightsLinearly() {
        let adapter = ElectrumTransactionsAdapter()

        var heightMap: [String: Int?] = [:]
        var posCache: [String: Int] = [:]
        var ids: [String] = []
        let total = 5_000
        let heightSpan = 200

        for index in 0..<total {
            let txid = "tx_\(index)"
            let height = 500 + (index % heightSpan)
            heightMap[txid] = height
            ids.append(txid)
            posCache["\(height)|\(txid)"] = index
        }

        adapter.debugSetHeightMap(heightMap)
        adapter.debugSetPosCache(posCache)

        // Using a Set to deduplicate heights makes the refinement step O(n) instead of O(n^2)
        // when many transactions share the same block height.
        var options = XCTMeasureOptions.default
        options.iterationCount = 5

        measure(metrics: [XCTClockMetric()], options: options) {
            let expectation = expectation(description: "refined order")
            Task {
                _ = try? await adapter.debugRefineOrder(ids: ids)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 2.0)
        }
    }
}
