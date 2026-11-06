import SwiftUI
import UIKit

/// Afbeelding verkleinen en bijsnijden zoals resizeIcon() in beheer.html (vullen, gecentreerd). iOS kan geen WebP
/// schrijven, dus JPEG (publish.php accepteert webp, png en jpg).
enum ImageTools {
    static func cover(_ image: UIImage, width: CGFloat, height: CGFloat, quality: CGFloat = 0.85) -> Data? {
        let size = CGSize(width: width, height: height)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let out = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            let s = max(width / image.size.width, height / image.size.height)
            let w = image.size.width * s, h = image.size.height * s
            image.draw(in: CGRect(x: (width - w) / 2, y: (height - h) / 2, width: w, height: h))
        }
        return out.jpegData(compressionQuality: quality)
    }

    /// Breedte maximaal `maxWidth`, verhouding blijft (portfolio- en reviewfoto's van PixelForges).
    static func fit(_ image: UIImage, maxWidth: CGFloat, quality: CGFloat = 0.82) -> Data? {
        let s = min(1, maxWidth / max(image.size.width, 1))
        return cover(image, width: (image.size.width * s).rounded(), height: (image.size.height * s).rounded(), quality: quality)
    }
}

/// Plaatje van de site: eerst een nog niet gepubliceerd bestand (pending), anders van de server.
struct SiteImage: View {
    let path: String
    let base: URL
    let pending: [String: Data]
    var contentMode: ContentMode = .fill

    var body: some View {
        if let d = pending[path], let ui = UIImage(data: d) {
            Image(uiImage: ui).resizable().aspectRatio(contentMode: contentMode)
        } else if !path.isEmpty, let url = path.hasPrefix("http") ? URL(string: path) : base.appendingPathComponent(path) as URL? {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(img): img.resizable().aspectRatio(contentMode: contentMode)
                default: Rectangle().fill(Theme.line)
                }
            }
        } else {
            Rectangle().fill(Theme.line)
        }
    }
}
