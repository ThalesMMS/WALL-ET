import Foundation
import Combine

class FeeOptimizationService {
    
    static let shared = FeeOptimizationService()
    private let electrumService = ElectrumService.shared
    // TransactionBuilder is initialized per use, not as singleton
    private var cancellables = Set<AnyCancellable>()
    
    // Fee estimation cache
    private var feeCache: [FeeLevel: Double] = [:]
    private var lastFeeUpdate = Date()
    private let cacheExpiration: TimeInterval = 600 // 10 minutes
    
    // MARK: - Fee Levels
    
    enum FeeLevel: String, CaseIterable {
        case slow = "Slow"
        case normal = "Normal"
        case fast = "Fast"
        case custom = "Custom"
        
        var targetBlocks: Int {
            switch self {
            case .slow: return 144    // ~24 hours
            case .normal: return 6     // ~1 hour
            case .fast: return 2       // ~20 minutes
            case .custom: return 0
            }
        }
        
        var description: String {
            switch self {
            case .slow: return "~24 hours"
            case .normal: return "~1 hour"
            case .fast: return "~20 minutes"
            case .custom: return "Custom"
            }
        }
        
        var color: String {
            switch self {
            case .slow: return "gray"
            case .normal: return "blue"
            case .fast: return "orange"
            case .custom: return "purple"
            }
        }
    }
    
    struct FeeEstimate {
        let level: FeeLevel
        let satsPerByte: Double
        let totalFee: Int64
        let estimatedTime: String
        let totalBytes: Int
    }
    
    // MARK: - Dynamic Fee Estimation
    
    func estimateFees(for transaction: BitcoinTransaction? = nil) async throws -> [FeeEstimate] {
        // Update cache if needed
        if Date().timeIntervalSince(lastFeeUpdate) > cacheExpiration {
            await updateFeeCache()
        }
        
        var estimates: [FeeEstimate] = []
        
        for level in FeeLevel.allCases where level != .custom {
            let satsPerByte: Double?
            if let cached = feeCache[level] {
                satsPerByte = cached
            } else {
                satsPerByte = await fetchFeeRate(for: level)
            }
            if let satsPerByte = satsPerByte {
                let estimate = calculateFeeEstimate(
                    level: level,
                    satsPerByte: satsPerByte,
                    transaction: transaction
                )
                estimates.append(estimate)
            }
        }
        
        return estimates
    }
    
    // MARK: - Private Helper Methods
    
    private func updateFeeCache() async {
        for level in FeeLevel.allCases where level != .custom {
            if let feeRate = await fetchFeeRate(for: level) {
                feeCache[level] = feeRate
            }
        }
        lastFeeUpdate = Date()
    }
    
    private func fetchFeeRate(for level: FeeLevel) async -> Double? {
        let blocks = level.targetBlocks
        
        return await withCheckedContinuation { continuation in
            electrumService.getFeeEstimate(blocks: blocks) { result in
                switch result {
                case .success(let feeRate):
                    // Convert from BTC per KB to sats per byte
                    let satsPerByte = feeRate * 100_000_000.0 / 1000.0
                    continuation.resume(returning: max(1.0, satsPerByte)) // Minimum 1 sat/byte
                case .failure(_):
                    // Fallback to hardcoded rates if Electrum fails
                    let fallbackRates: [FeeLevel: Double] = [
                        .slow: 5.0,
                        .normal: 20.0,
                        .fast: 50.0
                    ]
                    continuation.resume(returning: fallbackRates[level])
                }
            }
        }
    }
    
    private func calculateFeeEstimate(
        level: FeeLevel,
        satsPerByte: Double,
        transaction: BitcoinTransaction?
    ) -> FeeEstimate {
        // Estimate transaction size
        let estimatedVBytes: Int
        if let transaction = transaction {
            // Use actual transaction size if available
            estimatedVBytes = estimateTransactionSize(transaction)
        } else {
            // Default estimate: 1 input (P2WPKH), 2 outputs (P2WPKH), ~140 vbytes
            estimatedVBytes = 140
        }
        
        let totalFee = Int64(satsPerByte * Double(estimatedVBytes))
        
        return FeeEstimate(
            level: level,
            satsPerByte: satsPerByte,
            totalFee: totalFee,
            estimatedTime: level.description,
            totalBytes: estimatedVBytes
        )
    }
    
    private func estimateTransactionSize(_ transaction: BitcoinTransaction) -> Int {
        // Rough estimation based on transaction structure
        // Base transaction size: 4 bytes version + 4 bytes locktime = 8 bytes
        var size = 8
        
        // Inputs: each input is ~41 bytes (32 txid + 4 vout + 1 script length + 4 sequence)
        size += transaction.inputs.count * 41
        
        // Outputs: each output is ~9 bytes (8 value + 1 script length) + script size
        // P2WPKH script is 22 bytes
        size += transaction.outputs.count * (9 + 22)
        
        // Witness data: each input has witness (1 stack items + 1 item length + 72 bytes signature + 1 item length + 33 bytes pubkey)
        size += transaction.inputs.count * (1 + 1 + 72 + 1 + 33)
        
        return size
    }
    
    // MARK: - Error Types
    
    enum FeeOptimizationError: LocalizedError {
        case rbfNotEnabled
        case insufficientFeeBump
        case cannotBumpFee
        case noUnspentOutputs
        case parentFeeAlreadySufficient
        case insufficientFunds
        case invalidTransaction
        
        var errorDescription: String? {
            switch self {
            case .rbfNotEnabled:
                return "Transaction doesn't support RBF"
            case .insufficientFeeBump:
                return "New fee must be higher than original"
            case .cannotBumpFee:
                return "Cannot bump fee for this transaction"
            case .noUnspentOutputs:
                return "No unspent outputs available"
            case .parentFeeAlreadySufficient:
                return "Parent transaction fee is already sufficient"
            case .insufficientFunds:
                return "Insufficient funds for fee"
            case .invalidTransaction:
                return "Invalid transaction data"
            }
        }
    }
}

// MARK: - Protocol Conformance
extension FeeOptimizationService: FeeOptimizationServicing { }