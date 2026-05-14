import Foundation
import SwiftData

@Model
final class Photo {
    var id: UUID
    var shotAt: Date
    var dayKey: String
    var relativePath: String
    var note: String?
    var projectID: UUID?

    var project: Project?

    init(
        id: UUID = UUID(),
        shotAt: Date,
        dayKey: String,
        relativePath: String,
        note: String? = nil,
        projectID: UUID? = nil,
        project: Project? = nil
    ) {
        self.id = id
        self.shotAt = shotAt
        self.dayKey = dayKey
        self.relativePath = relativePath
        self.note = note
        self.projectID = projectID
        self.project = project
    }
}
