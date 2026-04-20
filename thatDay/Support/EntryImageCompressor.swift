import Foundation
import UIKit

nonisolated enum EntryImageCompressionError: LocalizedError {
    case invalidImageData
    case unableToSatisfySizeLimit

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            "The selected image could not be recognized. Choose a different image."
        case .unableToSatisfySizeLimit:
            "This image could not be compressed below 100KB. Choose a different image."
        }
    }
}

nonisolated enum EntryImageCompressor {
    static let maximumByteCount = 100 * 1024
    static let sizeLimitDescription = "100KB"

    private static let maximumPixelSizes: [CGFloat] = [1600, 1280, 1024, 896, 768, 640, 512, 384, 320, 256]
    private static let initialCompressionQuality: CGFloat = 0.92
    private static let minimumCompressionQuality: CGFloat = 0.2

    static func compressedData(for originalData: Data) throws -> Data {
        if isJPEGData(originalData), originalData.count <= maximumByteCount {
            return originalData
        }

        guard let sourceImage = UIImage(data: originalData) else {
            throw EntryImageCompressionError.invalidImageData
        }

        for maximumPixelSize in maximumPixelSizes {
            let resizedImage = resizedImage(from: sourceImage, maximumPixelSize: maximumPixelSize)
            if let compressedData = bestJPEGData(for: resizedImage) {
                return compressedData
            }
        }

        throw EntryImageCompressionError.unableToSatisfySizeLimit
    }

    private static func bestJPEGData(for image: UIImage) -> Data? {
        var lowerBound = minimumCompressionQuality
        var upperBound = initialCompressionQuality
        var bestData: Data?

        for _ in 0..<7 {
            let quality = (lowerBound + upperBound) / 2
            guard let data = image.jpegData(compressionQuality: quality) else {
                return nil
            }

            if data.count <= maximumByteCount {
                bestData = data
                lowerBound = quality
            } else {
                upperBound = quality
            }
        }

        if let bestData {
            return bestData
        }

        guard let fallbackData = image.jpegData(compressionQuality: minimumCompressionQuality),
              fallbackData.count <= maximumByteCount else {
            return nil
        }

        return fallbackData
    }

    private static func resizedImage(from image: UIImage, maximumPixelSize: CGFloat) -> UIImage {
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else {
            return image
        }

        let longestSide = max(originalSize.width, originalSize.height)
        guard longestSide > maximumPixelSize else {
            return image
        }

        let scale = maximumPixelSize / longestSide
        let targetSize = CGSize(
            width: max(1, floor(originalSize.width * scale)),
            height: max(1, floor(originalSize.height * scale))
        )
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1
        rendererFormat.opaque = true

        return UIGraphicsImageRenderer(size: targetSize, format: rendererFormat).image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private static func isJPEGData(_ data: Data) -> Bool {
        data.starts(with: [0xFF, 0xD8, 0xFF])
    }
}
