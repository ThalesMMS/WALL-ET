import UIKit
import CoreImage.CIFilterBuiltins

protocol QRCodeGenerating {
    func generate(from string: String) -> UIImage
}

struct QRCodeGenerator: QRCodeGenerating {
    private let context = CIContext()

    func generate(from string: String) -> UIImage {
        guard !string.isEmpty else { return UIImage(systemName: "xmark.circle") ?? UIImage() }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        guard let outputImage = filter.outputImage else {
            return UIImage(systemName: "xmark.circle") ?? UIImage()
        }

        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        if let cgImage = context.createCGImage(scaled, from: scaled.extent) {
            return UIImage(cgImage: cgImage)
        }

        return UIImage(systemName: "xmark.circle") ?? UIImage()
    }
}
