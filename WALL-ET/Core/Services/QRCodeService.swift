import Foundation
import CoreImage
import UIKit
import AVFoundation
import SwiftUI

class QRCodeService {
    
    static let shared = QRCodeService()
    private let context = CIContext()
    
    // MARK: - QR Code Generation
    
    func generateQRCode(from string: String, size: CGSize = CGSize(width: 300, height: 300)) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let scaleX = size.width / outputImage.extent.width
        let scaleY = size.height / outputImage.extent.height
        let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        let scaledImage = outputImage.transformed(by: transform)
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    func generateBitcoinQRCode(
        address: String,
        amount: Double? = nil,
        label: String? = nil,
        message: String? = nil
    ) -> UIImage? {
        var components = ["bitcoin:\(address)"]
        var params: [String] = []
        
        if let amount = amount {
            params.append("amount=\(amount)")
        }
        
        if let label = label?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            params.append("label=\(label)")
        }
        
        if let message = message?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            params.append("message=\(message)")
        }
        
        if !params.isEmpty {
            components.append("?")
            components.append(params.joined(separator: "&"))
        }
        
        let uri = components.joined()
        return generateQRCode(from: uri)
    }
    
    func generateTransactionQRCode(_ transaction: String) -> UIImage? {
        // For large transactions, use BBQR
        if transaction.count > 500 {
            return generateBBQR(from: transaction).first
        }
        return generateQRCode(from: transaction)
    }
    
    // MARK: - QR Code Parsing
    
    func parseBitcoinURI(_ uri: String) -> BitcoinURI? {
        guard uri.hasPrefix("bitcoin:") else { return nil }
        
        let components = uri.dropFirst(8).split(separator: "?", maxSplits: 1)
        guard !components.isEmpty else { return nil }
        
        let address = String(components[0])
        var amount: Double?
        var label: String?
        var message: String?
        
        if components.count > 1 {
            let params = String(components[1]).split(separator: "&")
            for param in params {
                let keyValue = param.split(separator: "=", maxSplits: 1)
                if keyValue.count == 2 {
                    let key = String(keyValue[0])
                    let value = String(keyValue[1])
                    
                    switch key {
                    case "amount":
                        amount = Double(value)
                    case "label":
                        label = value.removingPercentEncoding
                    case "message":
                        message = value.removingPercentEncoding
                    default:
                        break
                    }
                }
            }
        }
        
        return BitcoinURI(
            address: address,
            amount: amount,
            label: label,
            message: message
        )
    }
    
    struct BitcoinURI {
        let address: String
        let amount: Double?
        let label: String?
        let message: String?
    }
}

// MARK: - BBQR Support

extension QRCodeService {
    
    struct BBQR {
        let version: Int = 1
        let encoding: Encoding = .zlib
        let fileType: FileType
        let data: Data
        let splitSize: Int = 500
        
        enum Encoding: String {
            case hex = "H"
            case base32 = "2"
            case zlib = "Z"
        }
        
        enum FileType: String {
            case transaction = "T"
            case psbt = "P"
            case json = "J"
            case cbor = "C"
            case unicode = "U"
        }
    }
    
    func generateBBQR(from data: String, fileType: BBQR.FileType = .transaction) -> [UIImage] {
        guard let inputData = data.data(using: .utf8) else { return [] }
        
        // Compress data
        let compressedData = compress(inputData)
        
        // Split into chunks
        let chunks = splitIntoChunks(compressedData, chunkSize: 400)
        
        // Generate QR codes
        var qrCodes: [UIImage] = []
        for (index, chunk) in chunks.enumerated() {
            let header = createBBQRHeader(
                fileType: fileType,
                totalParts: chunks.count,
                currentPart: index + 1
            )
            
            let fullData = header + chunk.base64EncodedString()
            if let qr = generateQRCode(from: fullData) {
                qrCodes.append(qr)
            }
        }
        
        return qrCodes
    }
    
    func parseBBQR(_ qrCodes: [String]) -> String? {
        var parts: [(index: Int, data: String)] = []
        var totalParts: Int?
        var fileType: BBQR.FileType?
        
        for code in qrCodes {
            guard let (header, data) = parseBBQRPart(code) else { continue }
            
            if totalParts == nil {
                totalParts = header.total
                fileType = header.fileType
            }
            
            parts.append((header.index, data))
        }
        
        guard let total = totalParts,
              parts.count == total else { return nil }
        
        // Sort by index
        parts.sort { $0.index < $1.index }
        
        // Combine data
        let combinedData = parts.map { $0.data }.joined()
        guard let data = Data(base64Encoded: combinedData) else { return nil }
        
        // Decompress
        let decompressed = decompress(data)
        return String(data: decompressed, encoding: .utf8)
    }
    
    private func createBBQRHeader(
        fileType: BBQR.FileType,
        totalParts: Int,
        currentPart: Int
    ) -> String {
        return "B$\(fileType.rawValue)\(currentPart)/\(totalParts)/"
    }
    
    func parseBBQRPart(_ code: String) -> (header: (fileType: BBQR.FileType, index: Int, total: Int), data: String)? {
        guard code.hasPrefix("B$") else { return nil }
        
        let components = code.dropFirst(2).split(separator: "/")
        guard components.count >= 3 else { return nil }
        
        let typeAndIndex = String(components[0])
        guard !typeAndIndex.isEmpty else { return nil }
        
        let fileTypeRaw = String(typeAndIndex.prefix(1))
        let index = Int(typeAndIndex.dropFirst()) ?? 0
        let total = Int(components[1]) ?? 0
        
        guard let fileType = BBQR.FileType(rawValue: fileTypeRaw) else { return nil }
        
        let dataStartIndex = code.firstIndex(where: { String($0) == "/" })
        guard let startIndex = dataStartIndex else { return nil }
        
        let afterSecondSlash = code.index(after: code.index(after: startIndex))
        let data = String(code[afterSecondSlash...])
        
        return ((fileType, index, total), data)
    }
    
    private func splitIntoChunks(_ data: Data, chunkSize: Int) -> [Data] {
        var chunks: [Data] = []
        var offset = 0
        
        while offset < data.count {
            let remainingBytes = data.count - offset
            let currentChunkSize = min(chunkSize, remainingBytes)
            let chunk = data.subdata(in: offset..<(offset + currentChunkSize))
            chunks.append(chunk)
            offset += currentChunkSize
        }
        
        return chunks
    }
    
    private func compress(_ data: Data) -> Data {
        return (try? (data as NSData).compressed(using: .zlib) as Data) ?? data
    }
    
    private func decompress(_ data: Data) -> Data {
        return (try? (data as NSData).decompressed(using: .zlib) as Data) ?? data
    }
}