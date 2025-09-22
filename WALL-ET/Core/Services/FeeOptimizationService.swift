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
    
    // [... All other methods remain the same as in the resolved version ...]
    
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