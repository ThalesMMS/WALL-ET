import Foundation

// Minimal pure-Swift RIPEMD-160 implementation
// Based on the RIPEMD-160 specification (ISO/IEC 10118-3)

struct RIPEMD160 {
    static func hash(_ data: Data) -> Data {
        var message = [UInt8](data)
        let ml = UInt64(message.count) * 8
        // append the bit '1' to the message
        message.append(0x80)
        // append 0 <= k < 512 bits '0', such that the resulting message length (in bits)
        // is congruent to 448 (mod 512)
        while (message.count % 64) != 56 { message.append(0) }
        // append ml, the original message length, as a 64-bit little-endian integer
        message.append(contentsOf: withUnsafeBytes(of: ml.littleEndian, Array.init))

        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xefcdab89
        var h2: UInt32 = 0x98badcfe
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xc3d2e1f0

        // functions
        func f(_ j: Int, _ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
            switch j {
            case 0...15: return x ^ y ^ z
            case 16...31: return (x & y) | (~x & z)
            case 32...47: return (x | ~y) ^ z
            case 48...63: return (x & z) | (y & ~z)
            default: return x ^ (y | ~z)
            }
        }

        func K(_ j: Int) -> UInt32 {
            switch j { case 0...15: return 0x00000000
            case 16...31: return 0x5a827999
            case 32...47: return 0x6ed9eba1
            case 48...63: return 0x8f1bbcdc
            default: return 0xa953fd4e }
        }

        func Kp(_ j: Int) -> UInt32 {
            switch j { case 0...15: return 0x50a28be6
            case 16...31: return 0x5c4dd124
            case 32...47: return 0x6d703ef3
            case 48...63: return 0x7a6d76e9
            default: return 0x00000000 }
        }

        let r: [Int] = [
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
            7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
            3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
            1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
            4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13
        ]

        let rp: [Int] = [
            5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
            6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
            15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
            8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
            12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11
        ]

        let s: [Int] = [
            11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
            7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
            11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
            11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
            9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6
        ]

        let sp: [Int] = [
            8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
            9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
            9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
            15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
            8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11
        ]

        func rol(_ x: UInt32, _ n: Int) -> UInt32 {
            return (x << n) | (x >> (32 - n))
        }

        for chunk in stride(from: 0, to: message.count, by: 64) {
            var X = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let i4 = i * 4
                let b0 = UInt32(message[chunk + i4])
                let b1 = UInt32(message[chunk + i4 + 1]) << 8
                let b2 = UInt32(message[chunk + i4 + 2]) << 16
                let b3 = UInt32(message[chunk + i4 + 3]) << 24
                X[i] = b0 | b1 | b2 | b3
            }

            var al = h0, bl = h1, cl = h2, dl = h3, el = h4
            var ar = h0, br = h1, cr = h2, dr = h3, er = h4

            for j in 0..<80 {
                let jl = j
                let jr = 79 - j
                let tl = rol(al &+ f(jl, bl, cl, dl) &+ X[r[jl % 16]] &+ K(jl), s[jl]) &+ el
                al = el; el = dl; dl = rol(cl, 10); cl = bl; bl = tl

                let tr = rol(ar &+ f(jr, br, cr, dr) &+ X[rp[jr % 16]] &+ Kp(jr), sp[jr]) &+ er
                ar = er; er = dr; dr = rol(cr, 10); cr = br; br = tr
            }

            let t = h1 &+ cl &+ dr
            h1 = h2 &+ dl &+ er
            h2 = h3 &+ el &+ ar
            h3 = h4 &+ al &+ br
            h4 = h0 &+ bl &+ cr
            h0 = t
        }

        var digest = Data()
        [h0, h1, h2, h3, h4].forEach { h in
            var le = h.littleEndian
            withUnsafeBytes(of: &le) { digest.append(contentsOf: $0) }
        }
        return digest
    }
}

