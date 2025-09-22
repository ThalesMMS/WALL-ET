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
    
    private func calculateFeeEstimate(
        level: FeeLevel,
        satsPerByte: Double,
        transaction: BitcoinTransaction?
    ) -> FeeEstimate {
        // Calculate transaction size
        let txSize: Int
        if let tx = transaction {
            txSize = calculateTransactionSize(
                inputs: tx.inputs.count,
                outputs: tx.outputs.count,
                isSegwit: true
            )
        } else {
            // Default estimation for 1 input, 2 outputs
            txSize = calculateTransactionSize(
                inputs: 1,
                outputs: 2,
                isSegwit: true
            )
        }
        
        let totalFee = Int64(Double(txSize) * satsPerByte)
        
        return FeeEstimate(
            level: level,
            satsPerByte: satsPerByte,
            totalFee: totalFee,
            estimatedTime: level.description,
            totalBytes: txSize
        )
    }
    
    private func fetchFeeRate(for level: FeeLevel) async -> Double? {
        return await withCheckedContinuation { continuation in
            electrumService.getFeeEstimate(blocks: level.targetBlocks) { result in
                switch result {
                case .success(let feeRate):
                    // Convert from BTC/KB to sats/byte
                    let satsPerByte = feeRate * 100_000_000 / 1000
                    continuation.resume(returning: satsPerByte)
                case .failure:
                    // Fallback to default rates
                    let defaultRate: Double
                    switch level {
                    case .slow: defaultRate = 5
                    case .normal: defaultRate = 20
                    case .fast: defaultRate = 50
                    case .custom: defaultRate = 20
                    }
                    continuation.resume(returning: defaultRate)
                }
            }
        }
    }
    
    private func updateFeeCache() async {
        for level in FeeLevel.allCases where level != .custom {
            if let rate = await fetchFeeRate(for: level) {
                feeCache[level] = rate
            }
        }
        lastFeeUpdate = Date()
    }
    
    // MARK: - Replace-By-Fee (RBF)
    
    struct RBFTransaction {
        let originalTx: BitcoinTransaction
        let replacementTx: BitcoinTransaction
        let originalFee: Int64
        let newFee: Int64
        let feeBump: Double // Percentage increase
    }

    func createRBFTransaction(
        originalTxid: String,
        newFeeRate: Double,
        ownedAddresses: Set<String>
    ) async throws -> RBFTransaction {
        // Fetch original transaction
        let originalTx = try await fetchTransaction(txid: originalTxid)
        
        // Verify RBF is enabled (sequence < 0xFFFFFFFE)
        guard originalTx.inputs.allSatisfy({ $0.sequence < 0xFFFFFFFE }) else {
            throw FeeOptimizationError.rbfNotEnabled
        }
        
        // Calculate original fee
        let inputTotal = try await calculateInputTotal(for: originalTx)
        let outputTotal = originalTx.outputs.reduce(0) { $0 + $1.value }
        let originalFee = inputTotal - outputTotal
        
        // Calculate new fee
        let txSize = calculateTransactionSize(
            inputs: originalTx.inputs.count,
            outputs: originalTx.outputs.count,
            isSegwit: true
        )
        let newFee = Int64(Double(txSize) * newFeeRate)
        
        // Ensure fee bump is at least 1 sat/byte higher
        guard newFee > originalFee else {
            throw FeeOptimizationError.insufficientFeeBump
        }
        
        // Create new transaction with higher fee
        var newTx = originalTx
        
        // Reduce change output to pay for higher fee
        let network = electrumService.currentNetwork
        if let changeIndex = findChangeOutputIndex(in: originalTx, ownedAddresses: ownedAddresses, network: network) {
            let feeDifference = newFee - originalFee
            // Recreate the change output with reduced value
            let oldOutput = newTx.outputs[changeIndex]
            let newValue = oldOutput.value - feeDifference
            guard newValue >= 0 else {
                throw FeeOptimizationError.insufficientFunds
            }
            let newOutput = TransactionOutput(value: newValue, scriptPubKey: oldOutput.scriptPubKey)
            newTx.outputs[changeIndex] = newOutput

            // Ensure change output is still above dust threshold
            if newTx.outputs[changeIndex].value < 546 {
                // Remove change output if it's dust
                newTx.outputs.remove(at: changeIndex)
            }
        } else {
            // No change output, need to reduce payment amount
            throw FeeOptimizationError.cannotBumpFee
        }

        let feeBump = Double(newFee - originalFee) / Double(originalFee) * 100

        return RBFTransaction(
            originalTx: originalTx,
            replacementTx: newTx,
            originalFee: originalFee,
            newFee: newFee,
            feeBump: feeBump
        )
    }
    
    // MARK: - Child-Pays-For-Parent (CPFP)
    
    struct CPFPTransaction {
        let parentTxid: String
        let childTx: BitcoinTransaction
        let parentFee: Int64
        let childFee: Int64
        let effectiveFeeRate: Double
    }
    
    func createCPFPTransaction(
        parentTxid: String,
        targetFeeRate: Double
    ) async throws -> CPFPTransaction {
        // Fetch parent transaction
        let parentTx = try await fetchTransaction(txid: parentTxid)
        
        // Find unspent outputs from parent transaction
        let unspentOutputs = try await findUnspentOutputs(from: parentTxid)
        
        guard !unspentOutputs.isEmpty else {
            throw FeeOptimizationError.noUnspentOutputs
        }
        
        // Calculate parent fee
        let parentInputTotal = try await calculateInputTotal(for: parentTx)
        let parentOutputTotal = parentTx.outputs.reduce(0) { $0 + $1.value }
        let parentFee = parentInputTotal - parentOutputTotal
        
        // Calculate parent size
        let parentSize = calculateTransactionSize(
            inputs: parentTx.inputs.count,
            outputs: parentTx.outputs.count,
            isSegwit: true
        )
        
        // Calculate required child fee
        // Child must pay for both itself and make up for parent's low fee
        let childSize = calculateTransactionSize(
            inputs: unspentOutputs.count,
            outputs: 1, // Single output to self
            isSegwit: true
        )
        
        let totalSize = parentSize + childSize
        let targetTotalFee = Int64(Double(totalSize) * targetFeeRate)
        let childFee = targetTotalFee - parentFee
        
        // Ensure child fee is positive and sufficient
        guard childFee > 0 else {
            throw FeeOptimizationError.parentFeeAlreadySufficient
        }
        
        // Create child transaction
        let childInputs: [TransactionInput] = unspentOutputs.map { indexed in
            TransactionInput(
                previousOutput: Outpoint(
                    txid: Data(parentTxid.hexStringToData().reversed()),
                    vout: UInt32(indexed.index)
                ),
                scriptSig: Data(),
                sequence: 0xFFFFFFFD, // Enable RBF for child
                witness: []
            )
        }
        
        let inputAmount = unspentOutputs.reduce(0) { $0 + $1.output.value }
        let outputAmount = inputAmount - childFee
        
        // Ensure output is above dust threshold
        guard outputAmount >= 546 else {
            throw FeeOptimizationError.insufficientFunds
        }
        
        let childOutput = TransactionOutput(
            value: outputAmount,
            scriptPubKey: Data() // Would be filled with actual script
        )
        
        let childTx = BitcoinTransaction(
            version: 2,
            inputs: childInputs,
            outputs: [childOutput],
            lockTime: 0
        )
        
        let effectiveFeeRate = Double(targetTotalFee) / Double(totalSize)
        
        return CPFPTransaction(
            parentTxid: parentTxid,
            childTx: childTx,
            parentFee: parentFee,
            childFee: childFee,
            effectiveFeeRate: effectiveFeeRate
        )
    }
    
    // MARK: - Helper Methods
    
    private func fetchTransaction(txid: String) async throws -> BitcoinTransaction {
        return try await withCheckedThrowingContinuation { continuation in
            electrumService.getTransaction(txid) { result in
                switch result {
                case .success(let rawTx):
                    // Parse raw transaction
                    if let tx = self.parseRawTransaction(rawTx) {
                        continuation.resume(returning: tx)
                    } else {
                        continuation.resume(throwing: FeeOptimizationError.invalidTransaction)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func calculateInputTotal(for transaction: BitcoinTransaction) async throws -> Int64 {
        var total: Int64 = 0
        
        for input in transaction.inputs {
            // Fetch previous output to get amount
            let prevTxid = input.previousOutput.txid.hexString
            let prevTx = try await fetchTransaction(txid: prevTxid)
            let prevOutput = prevTx.outputs[Int(input.previousOutput.vout)]
            total += prevOutput.value
        }
        
        return total
    }
    
    private func findChangeOutputIndex(
        in transaction: BitcoinTransaction,
        ownedAddresses: Set<String>,
        network: BitcoinService.Network
    ) -> Int? {
        var candidate: Int?
        for (index, output) in transaction.outputs.enumerated() {
            guard let address = decodeAddress(scriptPubKey: output.scriptPubKey, network: network) else { continue }
            if ownedAddresses.contains(address) {
                candidate = index
            }
        }

        if let candidate = candidate {
            return candidate
        }

        return transaction.outputs.count > 1 ? transaction.outputs.count - 1 : nil
    }

    private func decodeAddress(scriptPubKey spk: Data, network: BitcoinService.Network) -> String? {
        let bytes = [UInt8](spk)

        if bytes.count == 22 && bytes[0] == 0x00 && bytes[1] == 0x14 {
            let prog = Data(bytes[2...])
            return Bech32.encode(hrp: network.bech32HRP, version: 0, program: prog)
        }

        if bytes.count == 34 && bytes[0] == 0x51 && bytes[1] == 0x20 {
            let prog = Data(bytes[2...])
            return Bech32.encode(hrp: network.bech32HRP, version: 1, program: prog)
        }

        if bytes.count == 25 && bytes[0] == 0x76 && bytes[1] == 0xa9 && bytes[2] == 0x14 && bytes[23] == 0x88 && bytes[24] == 0xac {
            let h160 = Data(bytes[3...22])
            var payload = Data([network.p2pkhVersion])
            payload.append(h160)
            return Base58.encode(payload)
        }

        if bytes.count == 23 && bytes[0] == 0xa9 && bytes[1] == 0x14 && bytes[22] == 0x87 {
            let h160 = Data(bytes[2...21])
            var payload = Data([network.p2shVersion])
            payload.append(h160)
            return Base58.encode(payload)
        }

        return nil
    }
    
    private struct IndexedOutput { let index: Int; let output: TransactionOutput }
    private func findUnspentOutputs(from txid: String) async throws -> [IndexedOutput] {
        // This would check which outputs from the transaction are unspent
        // Simplified for example
        return []
    }
    
    private func parseRawTransaction(_ rawTx: String) -> BitcoinTransaction? {
        // Parse raw transaction hex
        // Simplified - would use actual parsing logic
        return BitcoinTransaction(
            version: 2,
            inputs: [],
            outputs: [],
            lockTime: 0
        )
    }
    
    // MARK: - Fee Analysis
    
    func analyzeFeeMarket() async -> FeeMarketAnalysis {
        let currentFees = (try? await estimateFees()) ?? []
        
        // Get mempool statistics
        let mempoolSize = await getMempoolSize()
        let mempoolFees = await getMempoolFeeDistribution()
        
        // Calculate recommendations
        let recommendation = generateFeeRecommendation(
            currentFees: currentFees,
            mempoolSize: mempoolSize
        )
        
        return FeeMarketAnalysis(
            currentFees: currentFees,
            mempoolSize: mempoolSize,
            mempoolFeeDistribution: mempoolFees,
            recommendation: recommendation,
            timestamp: Date()
        )
    }

    // MARK: - Local size estimation (no external dependency)
    private func calculateTransactionSize(inputs: Int, outputs: Int, isSegwit: Bool) -> Int {
        var size = 10 // Version (4) + locktime (4) + varint counts (~2)
        size += outputs * 34
        size += inputs * (isSegwit ? 68 : 148)
        return size
    }
    
    private func getMempoolSize() async -> Int {
        // Would fetch actual mempool size
        return 50_000_000 // 50 MB example
    }
    
    private func getMempoolFeeDistribution() async -> [Double] {
        // Would fetch actual distribution
        return [1, 5, 10, 20, 50, 100, 200]
    }
    
    private func generateFeeRecommendation(
        currentFees: [FeeEstimate],
        mempoolSize: Int
    ) -> String {
        if mempoolSize > 100_000_000 {
            return "Network is congested. Consider using higher fees or waiting."
        } else if mempoolSize < 10_000_000 {
            return "Network is clear. Low fees should confirm quickly."
        } else {
            return "Normal network conditions. Standard fees recommended."
        }
    }
    
    struct FeeMarketAnalysis {
        let currentFees: [FeeEstimate]
        let mempoolSize: Int
        let mempoolFeeDistribution: [Double]
        let recommendation: String
        let timestamp: Date
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
