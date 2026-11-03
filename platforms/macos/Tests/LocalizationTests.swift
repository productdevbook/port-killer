import Foundation
import Testing
@testable import PortKiller

/**
 * Tests for English and Simplified Chinese (zh-Hans) localization lookups.
 */
struct LocalizationTests {

    @Test("Resolves English and Simplified Chinese strings from bundle")
    func translatesStaticKeys() {
        #expect(L10n.tr("All Ports", language: .english) == "All Ports")
        #expect(L10n.tr("All Ports", language: .simplifiedChinese) == "全部端口")

        #expect(L10n.tr("Web Server", language: .english) == "Web Server")
        #expect(L10n.tr("Web Server", language: .simplifiedChinese) == "Web 服务器")

        #expect(L10n.tr("Not running", language: .english) == "Not running")
        #expect(L10n.tr("Not running", language: .simplifiedChinese) == "未运行")
    }

    @Test("AppLanguage resolves expected locale codes")
    func languageCodes() {
        #expect(AppLanguage.english.resolvedCode == "en")
        #expect(AppLanguage.simplifiedChinese.resolvedCode == "zh-Hans")
        #expect(AppLanguage.english.locale.identifier == "en")
        #expect(AppLanguage.simplifiedChinese.locale.identifier == "zh-Hans")
    }
}
