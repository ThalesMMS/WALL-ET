import Foundation

final class FeeService: FeeServiceProtocol {
    func estimateFee(amount: Double, feeRate: Int) async throws -> Double {
        // Rough estimate: 1 input, 2 outputs, segwit ~ 140 vB
        let vbytes = 140
        return Double(feeRate * vbytes) / 100_000_000.0
    }
    func getFeeRates() async throws -> FeeRates { FeeRates(slow: 5, normal: 20, fast: 50, fastest: 100) }
    func getRecommendedFeeRate() async throws -> Int { 20 }
}

