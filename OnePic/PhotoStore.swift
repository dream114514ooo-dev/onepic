#if os(iOS)
import Foundation
import UIKit

enum PhotoStore {
    nonisolated static func url(for relativePath: String) -> URL {
        documentsDirectory.appendingPathComponent(relativePath, isDirectory: false)
    }

    nonisolated static func loadImage(relativePath: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: relativePath).path)
    }

    static func makeRelativePath(projectID: UUID, photoID: UUID) -> String {
        "Projects/\(projectID.uuidString)/photos/\(photoID.uuidString).jpg"
    }

    static func ensureProjectDirectory(projectID: UUID) throws -> URL {
        let url = documentsDirectory
            .appendingPathComponent("Projects", isDirectory: true)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }

    static func deletePhoto(relativePath: String) {
        let url = url(for: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteProjectDirectory(projectID: UUID) {
        let url = documentsDirectory
            .appendingPathComponent("Projects", isDirectory: true)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    nonisolated private static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
#endif
