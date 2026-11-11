import UIKit

/// Photos of a lab report become JPEG before the upload: the server only
/// extracts PDF, JPEG and PNG (HEIC would need an extra library there).
/// Large photos are scaled down so the long side is at most `maxSide` points,
/// which keeps them well below the 15 MB limit and still sharp enough to read.
enum LabUploadImage {
    static let maxSide: CGFloat = 3000

    /// JPEG data of an image file or photo (any format UIKit can read), or nil.
    static func jpeg(from data: Data, quality: CGFloat = 0.85) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return jpeg(from: image, quality: quality)
    }

    static func jpeg(from image: UIImage, quality: CGFloat = 0.85) -> Data? {
        let scaled = downscaled(image)
        var data = scaled.jpegData(compressionQuality: quality)
        // Very large scans: one more, stronger compression step.
        if let current = data, current.count > LabUpload.maxBytes {
            data = scaled.jpegData(compressionQuality: 0.6)
        }
        return data
    }

    /// Redraws the image at most `maxSide` on its long side (orientation applied).
    static func downscaled(_ image: UIImage) -> UIImage {
        let size = image.size
        let longSide = max(size.width, size.height)
        guard longSide > 0 else { return image }
        let factor = min(1, maxSide / longSide)
        let target = CGSize(width: floor(size.width * factor), height: floor(size.height * factor))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
