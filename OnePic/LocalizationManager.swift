import Foundation
import SwiftUI
import Combine

@MainActor
final class LocalizationManager: ObservableObject {
    private static let storageKey = "onepic_selectedLanguage"

    enum Language: String, CaseIterable, Identifiable {
        case en
        case zhHans = "zh-Hans"
        case th

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .en: return "English"
            case .zhHans: return "中文"
            case .th: return "ไทย"
            }
        }

        var localeIdentifier: String {
            rawValue
        }
    }

    @Published var language: Language {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: LocalizationManager.storageKey)
            bundle = LocalizationManager.makeBundle(for: language)
        }
    }

    @Published private(set) var bundle: Bundle

    init() {
        let stored = UserDefaults.standard.string(forKey: LocalizationManager.storageKey)
        let initial = Language(rawValue: stored ?? "") ?? .en
        self.language = initial
        self.bundle = LocalizationManager.makeBundle(for: initial)
    }

    var locale: Locale {
        Locale(identifier: language.localeIdentifier)
    }

    func setLanguage(_ language: Language) {
        self.language = language
    }

    func t(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    func tf(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), locale: locale, arguments: args)
    }

    private static func makeBundle(for language: Language) -> Bundle {
        if let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }
}
