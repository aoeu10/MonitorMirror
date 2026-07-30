import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct QRCodeView: View {
    let value: String

    @State private var image: UIImage?
    @State private var generationFailed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Pairing QR code")
            } else if generationFailed {
                ContentUnavailableView("Unable to create QR code", systemImage: "qrcode")
            } else {
                ProgressView("Creating private pairing code…")
                    .accessibilityLabel("Creating private pairing code")
            }
        }
        .task(id: value) {
            image = nil
            generationFailed = false

            let encodedValue = value
            let pngData = await Task.detached(priority: .userInitiated) {
                QRCodeRenderer.pngData(for: encodedValue)
            }.value

            guard !Task.isCancelled else { return }
            if let pngData, let rendered = UIImage(data: pngData) {
                image = rendered
            } else {
                generationFailed = true
            }
        }
    }
}

private enum QRCodeRenderer {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func pngData(for value: String) -> Data? {
        autoreleasepool {
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(value.utf8)
            filter.correctionLevel = "M"

            guard let output = filter.outputImage?.transformed(
                by: CGAffineTransform(scaleX: 12, y: 12)
            ) else {
                return nil
            }

            guard let cgImage = Self.context.createCGImage(output, from: output.extent) else {
                return nil
            }
            return UIImage(cgImage: cgImage).pngData()
        }
    }
}
