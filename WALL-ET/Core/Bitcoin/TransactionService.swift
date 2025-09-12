import Foundation
import CryptoKit

// MARK: - Transaction Service
class TransactionBuilder {
    
    // MARK: - Properties
    private let network: BitcoinService.Network
    private let bitcoinService: BitcoinService
    
    // MARK: - Constants
    struct Constants {
        static let dustLimit: Int64 = 546
        static let defaultSequence: UInt32 = 0xfffffffe // RBF enabled
        static let sighashAll: UInt8 = 0x01
        static let sighashNone: UInt8 = 0x02
        static let sighashSingle: UInt8 = 0x03
        static let sighashAnyoneCanPay: UInt8 = 0x80
    }
    
    // MARK: - Initialization
    init(network: BitcoinService.Network = .mainnet) {
        self.network = network
        self.bitcoinService = BitcoinService(network: network)
    }
    
    // MARK: - Transaction Building
    func buildTransaction(
        inputs: [UTXO],
        outputs: [(address: String, amount: Int64)],
        changeAddress: String,
        feeRate: Int // satoshis per vByte
    ) throws -> BitcoinTransaction {
        
        var transaction = BitcoinTransaction()
        
        // Add inputs
        for utxo in inputs {
            let input = TransactionInput(
                previousOutput: utxo.outpoint,
                scriptSig: Data(), // Will be filled during signing
                sequence: Constants.defaultSequence,
                witness: []
            )
            transaction.inputs.append(input)
        }
        
        // Add outputs
        var totalOutput: Int64 = 0
        for (address, amount) in outputs {
            guard amount >= Constants.dustLimit else {
                throw TransactionError.amountBelowDust
            }
            
            let scriptPubKey = try createScriptPubKey(for: address)
            let output = TransactionOutput(
                value: amount,
                scriptPubKey: scriptPubKey
            )
            transaction.outputs.append(output)
            totalOutput += amount
        }
        
        // Calculate fee
        let estimatedSize = estimateTransactionSize(
            inputs: inputs,
            outputs: transaction.outputs.count + 1 // +1 for potential change
        )
        let fee = Int64(estimatedSize * feeRate)
        
        // Calculate change
        let totalInput = inputs.reduce(0) { $0 + $1.value }
        let change = totalInput - totalOutput - fee
        
        // Add change output if above dust limit
        if change > Constants.dustLimit {
            let changeScriptPubKey = try createScriptPubKey(for: changeAddress)
            let changeOutput = TransactionOutput(
                value: change,
                scriptPubKey: changeScriptPubKey
            )
            transaction.outputs.append(changeOutput)
        } else if change < 0 {
            throw TransactionError.insufficientFunds
        }
        
        return transaction
    }
    
    // MARK: - Transaction Signing
    func signTransaction(
        _ transaction: inout BitcoinTransaction,
        with privateKeys: [Data],
        utxos: [UTXO]
    ) throws {
        
        guard transaction.inputs.count == privateKeys.count else {
            throw TransactionError.privateKeyMismatch
        }
        
        for (index, input) in transaction.inputs.enumerated() {
            let utxo = utxos[index]
            let privateKey = privateKeys[index]
            
            // Determine script type
            let scriptType = detectScriptType(utxo.scriptPubKey)
            
            switch scriptType {
            case .p2pkh:
                try signP2PKHInput(
                    &transaction,
                    inputIndex: index,
                    privateKey: privateKey,
                    prevScriptPubKey: utxo.scriptPubKey
                )
                
            case .p2wpkh:
                try signP2WPKHInput(
                    &transaction,
                    inputIndex: index,
                    privateKey: privateKey,
                    prevValue: utxo.value,
                    prevScriptPubKey: utxo.scriptPubKey
                )
                
            case .p2sh:
                // For P2SH-P2WPKH (nested SegWit)
                try signP2SHP2WPKHInput(
                    &transaction,
                    inputIndex: index,
                    privateKey: privateKey,
                    prevValue: utxo.value
                )
                
            default:
                throw TransactionError.unsupportedScriptType
            }
        }
    }
    
    private func signP2PKHInput(
        _ transaction: inout BitcoinTransaction,
        inputIndex: Int,
        privateKey: Data,
        prevScriptPubKey: Data
    ) throws {
        
        // Create signature hash
        let sigHash = createSignatureHash(
            transaction: transaction,
            inputIndex: inputIndex,
            scriptCode: prevScriptPubKey,
            sighashType: Constants.sighashAll
        )
        
        // Sign
        guard let signature = CryptoService.shared.signTransactionHash(sigHash, with: privateKey) else {
            throw TransactionError.signingFailed
        }
        var signatureWithSighash = signature
        signatureWithSighash.append(Constants.sighashAll)
        
        // Create scriptSig
        let publicKey = bitcoinService.derivePublicKey(from: privateKey, compressed: true)
        let scriptSig = createP2PKHScriptSig(signature: signatureWithSighash, publicKey: publicKey)
        
        transaction.inputs[inputIndex].scriptSig = scriptSig
    }
    
    private func signP2WPKHInput(
        _ transaction: inout BitcoinTransaction,
        inputIndex: Int,
        privateKey: Data,
        prevValue: Int64,
        prevScriptPubKey: Data
    ) throws {
        
        // Create signature hash for SegWit
        let sigHash = createSegwitSignatureHash(
            transaction: transaction,
            inputIndex: inputIndex,
            scriptCode: prevScriptPubKey,
            value: prevValue,
            sighashType: Constants.sighashAll
        )
        
        // Sign
        guard let signature = CryptoService.shared.signTransactionHash(sigHash, with: privateKey) else {
            throw TransactionError.signingFailed
        }
        var signatureWithSighash = signature
        signatureWithSighash.append(Constants.sighashAll)
        
        // Create witness
        let publicKey = bitcoinService.derivePublicKey(from: privateKey, compressed: true)
        transaction.inputs[inputIndex].witness = [signatureWithSighash, publicKey]
    }
    
    private func signP2SHP2WPKHInput(
        _ transaction: inout BitcoinTransaction,
        inputIndex: Int,
        privateKey: Data,
        prevValue: Int64
    ) throws {
        
        let publicKey = bitcoinService.derivePublicKey(from: privateKey, compressed: true)
        let pubKeyHash = hash160(publicKey)
        
        // Create redeem script (P2WPKH)
        var redeemScript = Data()
        redeemScript.append(0x00) // OP_0
        redeemScript.append(0x14) // Push 20 bytes
        redeemScript.append(pubKeyHash)
        
        // Sign as P2WPKH
        let scriptCode = createP2PKHScriptCode(pubKeyHash: pubKeyHash)
        let sigHash = createSegwitSignatureHash(
            transaction: transaction,
            inputIndex: inputIndex,
            scriptCode: scriptCode,
            value: prevValue,
            sighashType: Constants.sighashAll
        )
        
        guard let signature = CryptoService.shared.signTransactionHash(sigHash, with: privateKey) else {
            throw TransactionError.signingFailed
        }
        var signatureWithSighash = signature
        signatureWithSighash.append(Constants.sighashAll)
        
        // Set scriptSig (just the redeem script)
        transaction.inputs[inputIndex].scriptSig = pushData(redeemScript)
        
        // Set witness
        transaction.inputs[inputIndex].witness = [signatureWithSighash, publicKey]
    }
    
    // MARK: - Script Creation
    private func createScriptPubKey(for address: String) throws -> Data {
        if let decoded = Base58.decode(address) {
            let version = decoded[0]
            let hash = decoded[1..<21]
            
            if version == network.p2pkhVersion {
                // P2PKH
                return createP2PKHScriptPubKey(hash: hash)
            } else if version == network.p2shVersion {
                // P2SH
                return createP2SHScriptPubKey(hash: hash)
            }
        } else if let (version, program) = Bech32.decode(address) {
            if version == 0 && program.count == 20 {
                // P2WPKH
                return createP2WPKHScriptPubKey(hash: program)
            } else if version == 0 && program.count == 32 {
                // P2WSH
                return createP2WSHScriptPubKey(hash: program)
            } else if version == 1 && program.count == 32 {
                // P2TR (Taproot)
                return createP2TRScriptPubKey(hash: program)
            }
        }
        
        throw TransactionError.invalidAddress
    }
    
    private func createP2PKHScriptPubKey(hash: Data) -> Data {
        var script = Data()
        script.append(0x76) // OP_DUP
        script.append(0xa9) // OP_HASH160
        script.append(0x14) // Push 20 bytes
        script.append(hash)
        script.append(0x88) // OP_EQUALVERIFY
        script.append(0xac) // OP_CHECKSIG
        return script
    }
    
    private func createP2SHScriptPubKey(hash: Data) -> Data {
        var script = Data()
        script.append(0xa9) // OP_HASH160
        script.append(0x14) // Push 20 bytes
        script.append(hash)
        script.append(0x87) // OP_EQUAL
        return script
    }
    
    private func createP2WPKHScriptPubKey(hash: Data) -> Data {
        var script = Data()
        script.append(0x00) // OP_0
        script.append(0x14) // Push 20 bytes
        script.append(hash)
        return script
    }
    
    private func createP2WSHScriptPubKey(hash: Data) -> Data {
        var script = Data()
        script.append(0x00) // OP_0
        script.append(0x20) // Push 32 bytes
        script.append(hash)
        return script
    }
    
    private func createP2TRScriptPubKey(hash: Data) -> Data {
        var script = Data()
        script.append(0x51) // OP_1
        script.append(0x20) // Push 32 bytes
        script.append(hash)
        return script
    }
    
    private func createP2PKHScriptSig(signature: Data, publicKey: Data) -> Data {
        var script = Data()
        script.append(pushData(signature))
        script.append(pushData(publicKey))
        return script
    }
    
    private func createP2PKHScriptCode(pubKeyHash: Data) -> Data {
        var script = Data()
        script.append(0x76) // OP_DUP
        script.append(0xa9) // OP_HASH160
        script.append(0x14) // Push 20 bytes
        script.append(pubKeyHash)
        script.append(0x88) // OP_EQUALVERIFY
        script.append(0xac) // OP_CHECKSIG
        return script
    }
    
    // MARK: - Signature Hash Creation
    private func createSignatureHash(
        transaction: BitcoinTransaction,
        inputIndex: Int,
        scriptCode: Data,
        sighashType: UInt8
    ) -> Data {
        
        var preimage = Data()
        
        // Version
        preimage.append(transaction.version.littleEndianData)
        
        // Inputs
        preimage.append(compactSizeEncoding(transaction.inputs.count))
        for (index, input) in transaction.inputs.enumerated() {
            preimage.append(input.previousOutput.serialize())
            
            if index == inputIndex {
                preimage.append(compactSizeEncoding(scriptCode.count))
                preimage.append(scriptCode)
            } else {
                preimage.append(compactSizeEncoding(0))
            }
            
            preimage.append(input.sequence.littleEndianData)
        }
        
        // Outputs
        preimage.append(compactSizeEncoding(transaction.outputs.count))
        for output in transaction.outputs {
            preimage.append(output.serialize())
        }
        
        // Locktime
        preimage.append(transaction.lockTime.littleEndianData)
        
        // Sighash type
        var sighashBytes = UInt32(sighashType).littleEndian
        preimage.append(Data(bytes: &sighashBytes, count: 4))
        
        // Double SHA256
        return sha256(sha256(preimage))
    }
    
    private func createSegwitSignatureHash(
        transaction: BitcoinTransaction,
        inputIndex: Int,
        scriptCode: Data,
        value: Int64,
        sighashType: UInt8
    ) -> Data {
        
        var preimage = Data()
        
        // Version
        preimage.append(transaction.version.littleEndianData)
        
        // Hash of all outpoints
        let outpointsHash = hashPrevouts(transaction: transaction)
        preimage.append(outpointsHash)
        
        // Hash of all sequences
        let sequencesHash = hashSequences(transaction: transaction)
        preimage.append(sequencesHash)
        
        // Outpoint of current input
        preimage.append(transaction.inputs[inputIndex].previousOutput.serialize())
        
        // Script code
        preimage.append(compactSizeEncoding(scriptCode.count))
        preimage.append(scriptCode)
        
        // Value
        preimage.append(value.littleEndianData)
        
        // Sequence
        preimage.append(transaction.inputs[inputIndex].sequence.littleEndianData)
        
        // Hash of all outputs
        let outputsHash = hashOutputs(transaction: transaction)
        preimage.append(outputsHash)
        
        // Locktime
        preimage.append(transaction.lockTime.littleEndianData)
        
        // Sighash type
        var sighashBytes = UInt32(sighashType).littleEndian
        preimage.append(Data(bytes: &sighashBytes, count: 4))
        
        // Double SHA256
        return sha256(sha256(preimage))
    }
    
    // MARK: - Helper Functions
    private func estimateTransactionSize(inputs: [UTXO], outputs: Int) -> Int {
        // Base size
        var size = 10 // Version (4) + Locktime (4) + Input/Output count (2)
        
        // Input size estimation
        for utxo in inputs {
            let scriptType = detectScriptType(utxo.scriptPubKey)
            switch scriptType {
            case .p2pkh:
                size += 148 // P2PKH input
            case .p2wpkh:
                size += 68 // P2WPKH input (with witness discount)
            case .p2sh:
                size += 91 // P2SH-P2WPKH input
            default:
                size += 148 // Conservative estimate
            }
        }
        
        // Output size
        size += outputs * 34 // Standard output size
        
        return size
    }
    
    private func detectScriptType(_ script: Data) -> ScriptType {
        if script.count == 25 && script[0] == 0x76 && script[1] == 0xa9 {
            return .p2pkh
        } else if script.count == 23 && script[0] == 0xa9 {
            return .p2sh
        } else if script.count == 22 && script[0] == 0x00 && script[1] == 0x14 {
            return .p2wpkh
        } else if script.count == 34 && script[0] == 0x00 && script[1] == 0x20 {
            return .p2wsh
        } else if script.count == 34 && script[0] == 0x51 && script[1] == 0x20 {
            return .p2tr
        }
        return .unknown
    }
    
    private func pushData(_ data: Data) -> Data {
        var result = Data()
        
        if data.count < 76 {
            result.append(UInt8(data.count))
        } else if data.count <= 0xff {
            result.append(0x4c) // OP_PUSHDATA1
            result.append(UInt8(data.count))
        } else if data.count <= 0xffff {
            result.append(0x4d) // OP_PUSHDATA2
            result.append(UInt16(data.count).littleEndianData)
        } else {
            result.append(0x4e) // OP_PUSHDATA4
            result.append(UInt32(data.count).littleEndianData)
        }
        
        result.append(data)
        return result
    }
    
    private func compactSizeEncoding(_ value: Int) -> Data {
        if value < 0xfd {
            return Data([UInt8(value)])
        } else if value <= 0xffff {
            var data = Data([0xfd])
            data.append(UInt16(value).littleEndianData)
            return data
        } else if value <= 0xffffffff {
            var data = Data([0xfe])
            data.append(UInt32(value).littleEndianData)
            return data
        } else {
            var data = Data([0xff])
            data.append(UInt64(value).littleEndianData)
            return data
        }
    }
    
    private func hash160(_ data: Data) -> Data {
        let sha256Hash = SHA256.hash(data: data)
        // Simplified - use actual RIPEMD160
        return Data(sha256Hash.prefix(20))
    }
    
    private func sha256(_ data: Data) -> Data {
        return SHA256.hash(data: data).data
    }
    
    private func hashPrevouts(transaction: BitcoinTransaction) -> Data {
        var data = Data()
        for input in transaction.inputs {
            data.append(input.previousOutput.serialize())
        }
        return sha256(sha256(data))
    }
    
    private func hashSequences(transaction: BitcoinTransaction) -> Data {
        var data = Data()
        for input in transaction.inputs {
            data.append(input.sequence.littleEndianData)
        }
        return sha256(sha256(data))
    }
    
    private func hashOutputs(transaction: BitcoinTransaction) -> Data {
        var data = Data()
        for output in transaction.outputs {
            data.append(output.serialize())
        }
        return sha256(sha256(data))
    }
}

// MARK: - Transaction Structure
struct BitcoinTransaction {
    var version: Int32 = 2
    var inputs: [TransactionInput] = []
    var outputs: [TransactionOutput] = []
    var witness: [[Data]] = []
    var lockTime: UInt32 = 0
    
    func serialize() -> Data {
        var data = Data()
        
        // Version
        data.append(version.littleEndianData)
        
        // Marker and flag for SegWit
        let hasWitness = inputs.contains { !$0.witness.isEmpty }
        if hasWitness {
            data.append(0x00) // Marker
            data.append(0x01) // Flag
        }
        
        // Inputs
        data.append(compactSizeEncoding(inputs.count))
        for input in inputs {
            data.append(input.serialize())
        }
        
        // Outputs
        data.append(compactSizeEncoding(outputs.count))
        for output in outputs {
            data.append(output.serialize())
        }
        
        // Witness data
        if hasWitness {
            for input in inputs {
                data.append(compactSizeEncoding(input.witness.count))
                for witnessItem in input.witness {
                    data.append(compactSizeEncoding(witnessItem.count))
                    data.append(witnessItem)
                }
            }
        }
        
        // Locktime
        data.append(lockTime.littleEndianData)
        
        return data
    }
    
    var txid: String {
        let serialized = serialize()
        let hash = sha256(sha256(serialized))
        return Data(hash.reversed()).hexString
    }
}

struct TransactionInput {
    let previousOutput: Outpoint
    var scriptSig: Data
    let sequence: UInt32
    var witness: [Data]
    
    func serialize() -> Data {
        var data = Data()
        data.append(previousOutput.serialize())
        data.append(compactSizeEncoding(scriptSig.count))
        data.append(scriptSig)
        data.append(sequence.littleEndianData)
        return data
    }
}

struct TransactionOutput {
    let value: Int64
    let scriptPubKey: Data
    
    func serialize() -> Data {
        var data = Data()
        data.append(value.littleEndianData)
        data.append(compactSizeEncoding(scriptPubKey.count))
        data.append(scriptPubKey)
        return data
    }
}

struct Outpoint {
    let txid: Data
    let vout: UInt32
    
    func serialize() -> Data {
        var data = Data()
        data.append(txid)
        data.append(vout.littleEndianData)
        return data
    }
}

struct UTXO {
    let outpoint: Outpoint
    let value: Int64
    let scriptPubKey: Data
    let address: String
    let confirmations: Int
}

// MARK: - Enums
enum ScriptType {
    case p2pkh
    case p2sh
    case p2wpkh
    case p2wsh
    case p2tr
    case unknown
}

enum TransactionError: LocalizedError {
    case insufficientFunds
    case amountBelowDust
    case invalidAddress
    case privateKeyMismatch
    case unsupportedScriptType
    case signingFailed
    
    var errorDescription: String? {
        switch self {
        case .insufficientFunds:
            return "Insufficient funds for transaction"
        case .amountBelowDust:
            return "Output amount below dust limit"
        case .invalidAddress:
            return "Invalid Bitcoin address"
        case .privateKeyMismatch:
            return "Number of private keys doesn't match inputs"
        case .unsupportedScriptType:
            return "Unsupported script type"
        case .signingFailed:
            return "Failed to sign transaction"
        }
    }
}

// MARK: - Helper Extensions
extension FixedWidthInteger {
    var littleEndianData: Data {
        return withUnsafeBytes(of: littleEndian) { Data($0) }
    }
}

extension Data {
    var hexString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
}

private func compactSizeEncoding(_ value: Int) -> Data {
    if value < 0xfd {
        return Data([UInt8(value)])
    } else if value <= 0xffff {
        var data = Data([0xfd])
        data.append(UInt16(value).littleEndianData)
        return data
    } else if value <= 0xffffffff {
        var data = Data([0xfe])
        data.append(UInt32(value).littleEndianData)
        return data
    } else {
        var data = Data([0xff])
        data.append(UInt64(value).littleEndianData)
        return data
    }
}

private func sha256(_ data: Data) -> Data {
    return SHA256.hash(data: data).data
}