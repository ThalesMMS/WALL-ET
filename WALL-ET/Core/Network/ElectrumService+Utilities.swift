import Foundation

extension String {
    func hexStringToData() -> Data {
        var data = Data()
        var hex = self

        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }

        if hex.count % 2 != 0 {
            hex = "0" + hex
        }

        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            let byteString = hex[index..<nextIndex]
            if let byte = UInt8(byteString, radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }

        return data
    }
}
