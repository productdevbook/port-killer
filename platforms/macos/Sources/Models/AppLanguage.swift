/**
 * AppLanguage.swift
 * PortKiller
 *
 * Application language preference and localization lookup helpers.
 */

import Foundation
import SwiftUI
import Defaults

/// Supported application display languages.
enum AppLanguage: String, CaseIterable, Codable, Defaults.Serializable, Sendable {
    case system = "system"
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    /// Localized display label for the language picker.
    var displayName: String {
        switch self {
        case .system: return L10n.tr("System Default")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }

    /// Effective language code ("en" or "zh-Hans").
    var resolvedCode: String {
        switch self {
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("zh") ? "zh-Hans" : "en"
        }
    }

    /// Locale to inject into the SwiftUI environment.
    var locale: Locale {
        Locale(identifier: resolvedCode)
    }
}

/// Localization helper that resolves strings from the active language bundle.
enum L10n {
    /// Locate the parent resource bundle (Contents/Resources/PortKiller_PortKiller.bundle or Bundle.main).
    private static var baseCategories: [Bundle] {
        var bundles: [Bundle] = [Bundle.main]
        let bundleName = "PortKiller_PortKiller.bundle"
        if let resourceURL = Bundle.main.resourceURL,
           let bundle = Bundle(url: resourceURL.appendingPathComponent(bundleName)) {
            bundles.insert(bundle, at: 0)
        } else if let bundle = Bundle(url: Bundle.main.bundleURL.appendingPathComponent(bundleName)) {
            bundles.insert(bundle, at: 0)
        }
        bundles.append(Bundle.module)
        return bundles
    }

    /// Returns the `.lproj` bundle for the specified language code.
    static func bundle(for code: String) -> Bundle {
        for candidate in baseCategories {
            if let path = candidate.path(forResource: code, ofType: "lproj"),
               let lproj = Bundle(path: path) {
                return lproj
            }
            if let path = candidate.path(forResource: code.lowercased(), ofType: "lproj"),
               let lproj = Bundle(path: path) {
                return lproj
            }
        }
        return Bundle.main
    }

    /// Returns the `.lproj` bundle for the active `AppLanguage`.
    static var bundle: Bundle {
        bundle(for: Defaults[.appLanguage].resolvedCode)
    }

    /// Translates a static key using the active language bundle.
    static func tr(_ key: String, language: AppLanguage? = nil) -> String {
        let targetBundle = language.map { bundle(for: $0.resolvedCode) } ?? bundle
        return targetBundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// Translates a format key with arguments using the active language bundle.
    static func format(_ key: String, _ args: CVarArg...) -> String {
        let formatString = tr(key)
        return String(format: formatString, locale: Defaults[.appLanguage].locale, arguments: args)
    }
}
