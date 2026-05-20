import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID
    var name: String
    var createdAt: Date
    var lastOpenedAt: Date
    var currentStreak: Int
    var bestStreak: Int
    var lastShotDayKey: String?
    var ghostEnabled: Bool
    var ghostOpacity: Double
    var ghostPhotoID: UUID?
    var reminderMinutes: Int?

    @Relationship(deleteRule: .cascade, inverse: \Photo.project)
    var photos: [Photo]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        lastOpenedAt: Date = Date(),
        currentStreak: Int = 0,
        bestStreak: Int = 0,
        lastShotDayKey: String? = nil,
        ghostEnabled: Bool = false,
        ghostOpacity: Double = 0.4,
        ghostPhotoID: UUID? = nil,
        reminderMinutes: Int? = nil,
        photos: [Photo] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        self.currentStreak = currentStreak
        self.bestStreak = bestStreak
        self.lastShotDayKey = lastShotDayKey
        self.ghostEnabled = ghostEnabled
        self.ghostOpacity = ghostOpacity
        self.ghostPhotoID = ghostPhotoID
        self.reminderMinutes = reminderMinutes
        self.photos = photos
    }

    @discardableResult
    func registerShot(at date: Date) -> Bool {
        let calendar = Calendar.current
        let todayKey = DayKey.make(for: date, calendar: calendar)

        if lastShotDayKey == todayKey {
            return false
        }

        if let lastKey = lastShotDayKey,
           let lastDate = DayKey.parse(lastKey, calendar: calendar) {
            let dayDiff = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastDate), to: calendar.startOfDay(for: date)).day ?? 0
            if dayDiff == 1 {
                currentStreak += 1
            } else {
                currentStreak = 1
            }
        } else {
            currentStreak = 1
        }

        lastShotDayKey = todayKey
        bestStreak = max(bestStreak, currentStreak)
        return true
    }
}
