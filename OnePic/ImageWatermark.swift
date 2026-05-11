#if os(iOS)
import Foundation
import UIKit

enum ImageWatermark {
    static func applyDate(_ date: Date, to image: UIImage) -> UIImage {
        let text = dateString(from: date)
        let fontSize = max(18, min(image.size.width, image.size.height) * 0.04)
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white.withAlphaComponent(0.92),
            .paragraphStyle: paragraph,
            .shadow: shadow
        ]

        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: image.size))

            let padding = max(16, fontSize * 0.8)
            let maxWidth = image.size.width - padding * 2
            let bounding = (text as NSString).boundingRect(
                with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )

            let rect = CGRect(
                x: image.size.width - padding - bounding.width,
                y: image.size.height - padding - bounding.height,
                width: bounding.width,
                height: bounding.height
            ).integral

            (text as NSString).draw(in: rect, withAttributes: attributes)
        }
    }

    private static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static var shadow: NSShadow {
        let s = NSShadow()
        s.shadowColor = UIColor.black.withAlphaComponent(0.55)
        s.shadowBlurRadius = 6
        s.shadowOffset = CGSize(width: 0, height: 2)
        return s
    }
}
#endif
