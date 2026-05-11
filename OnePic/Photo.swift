import Foundation
import SwiftData

@Model
final class Photo {
    var id: UUID
    var shotAt: Date
    var dayKey: String
    var relativePath: String
    var projectID: UUID?

    var project: Project?

    init(
        id: UUID = UUID(),
        shotAt: Date,
        dayKey: String,
        relativePath: String,
        projectID: UUID? = nil,
        project: Project? = nil
    ) {
        self.id = id
        self.shotAt = shotAt
        self.dayKey = dayKey
        self.relativePath = relativePath
        self.projectID = projectID
        self.project = project
    }
}
