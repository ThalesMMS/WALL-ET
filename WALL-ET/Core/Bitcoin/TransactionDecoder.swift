import Foundation

struct DecodedTransaction {
    struct Input {
        let prevTxid: String
        let vout: Int
        let sequence: UInt32
    }
    struct Output {
        let value: Int64
        let scriptPubKey: Data
        let address: String?
    }
    let version: Int32
    let inputs: [Input]
    let outputs: [Output]
    let lockTime: UInt32
}

final class TransactionDecoder {
    private let network: BitcoinService.Network
    init(network: BitcoinService.Network) { self.network = network }

    func decode(rawHex: String) throws -> DecodedTransaction {
        guard let data = Data(hex: rawHex) else { throw DecodeError.invalidHex }
        var r = Reader(data)

        let version = Int32(bitPattern: r.readUInt32LE())

        // Detect segwit marker/flag
        var hasWitness = false
        let marker = r.peekByte()
        if marker == 0x00 {
            _ = r.readUInt8() // marker
            let flag = r.readUInt8()
            if flag != 0 { hasWitness = true }
        }

        let vinCount = Int(r.readVarInt())
        var inputs: [DecodedTransaction.Input] = []
        inputs.reserveCapacity(vinCount)
        for _ in 0..<vinCount {
            let prevHashLE = r.readBytes(32)
            let prevTxid = Data(prevHashLE.reversed()).hexString
            let vout = Int(r.readUInt32LE())
            let scriptLen = Int(r.readVarInt())
            _ = r.readBytes(scriptLen) // scriptSig (ignored)
            let sequence = r.readUInt32LE()
            inputs.append(.init(prevTxid: prevTxid, vout: vout, sequence: sequence))
        }

        let voutCount = Int(r.readVarInt())
        var outputs: [DecodedTransaction.Output] = []
        outputs.reserveCapacity(voutCount)
        for _ in 0..<voutCount {
            let value = Int64(bitPattern: r.readUInt64LE())
            let scriptLen = Int(r.readVarInt())
            let spk = Data(r.readBytes(scriptLen))
            let address = decodeAddress(scriptPubKey: spk)
            outputs.append(.init(value: value, scriptPubKey: spk, address: address))
        }

        if hasWitness {
            // Skip witness stacks
            for _ in 0..<vinCount {
                let nStack = Int(r.readVarInt())
                for _ in 0..<nStack {
                    let len = Int(r.readVarInt())
                    _ = r.readBytes(len)
                }
            }
        }

        let lockTime = r.readUInt32LE()
        return .init(version: version, inputs: inputs, outputs: outputs, lockTime: lockTime)
    }

    private func decodeAddress(scriptPubKey spk: Data) -> String? {
        let bytes = [UInt8](spk)
        // P2WPKH: 0x00 0x14 <20>
        if bytes.count == 22 && bytes[0] == 0x00 && bytes[1] == 0x14 {
            let prog = Data(bytes[2...])
            return Bech32.encode(hrp: network.bech32HRP, version: 0, program: prog)
        }
        // P2TR: 0x51 0x20 <32>
        if bytes.count == 34 && bytes[0] == 0x51 && bytes[1] == 0x20 {
            let prog = Data(bytes[2...])
            return Bech32.encode(hrp: network.bech32HRP, version: 1, program: prog)
        }
        // P2PKH: OP_DUP OP_HASH160 PUSH20 <20> OP_EQUALVERIFY OP_CHECKSIG
        if bytes.count == 25 && bytes[0] == 0x76 && bytes[1] == 0xa9 && bytes[2] == 0x14 && bytes[23] == 0x88 && bytes[24] == 0xac {
            let h160 = Data(bytes[3...22])
            var payload = Data([network.p2pkhVersion])
            payload.append(h160)
            return Base58.encode(payload)
        }
        // P2SH: OP_HASH160 PUSH20 <20> OP_EQUAL
        if bytes.count == 23 && bytes[0] == 0xa9 && bytes[1] == 0x14 && bytes[22] == 0x87 {
            let h160 = Data(bytes[2...21])
            var payload = Data([network.p2shVersion])
            payload.append(h160)
            return Base58.encode(payload)
        }
        return nil
    }

    enum DecodeError: Error { case invalidHex, outOfBounds }

    private struct Reader {
        let bytes: [UInt8]
        var offset: Int = 0
        init(_ data: Data) { self.bytes = [UInt8](data) }
        mutating func readUInt8() -> UInt8 { defer { offset += 1 }; return bytes[offset] }
        mutating func readBytes(_ n: Int) -> [UInt8] { defer { offset += n }; return Array(bytes[offset..<offset+n]) }
        mutating func readUInt32LE() -> UInt32 {
            let b = readBytes(4)
            return UInt32(b[0]) | (UInt32(b[1]) << 8) | (UInt32(b[2]) << 16) | (UInt32(b[3]) << 24)
        }
        mutating func readUInt64LE() -> UInt64 {
            let b = readBytes(8)
            var v: UInt64 = 0
            for i in 0..<8 { v |= (UInt64(b[i]) << (8*UInt64(i))) }
            return v
        }
        mutating func readVarInt() -> UInt64 {
            let prefix = readUInt8()
            switch prefix {
            case 0xfd:
                let b = readBytes(2)
                return UInt64(UInt16(b[0]) | (UInt16(b[1]) << 8))
            case 0xfe:
                return UInt64(readUInt32LE())
            case 0xff:
                return readUInt64LE()
            default:
                return UInt64(prefix)
            }
        }
        func peekByte() -> UInt8 { bytes[offset] }
    }
}

private extension Data {
    init?(hex: String) {
        var hex = hex
        if hex.count % 2 != 0 { hex = "0" + hex }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count/2)
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard next <= hex.endIndex else { return nil }
            let byteStr = hex[idx..<next]
            guard let b = UInt8(byteStr, radix: 16) else { return nil }
            bytes.append(b)
            idx = next
        }
        self = Data(bytes)
    }
}
