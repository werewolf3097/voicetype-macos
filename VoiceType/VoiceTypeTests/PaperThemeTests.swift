import XCTest
@testable import VoiceTypeTests

final class PaperThemeTests: XCTestCase {
    func testPhase1ThemesMeetMinimumWCAGContrast() {
        let themes: [PaperTheme] = [.cleanSheet, .cotton, .graphite]
        for theme in themes {
            let inkContrast = theme.base.contrastRatio(with: theme.ink)
            let secondaryContrast = theme.base.contrastRatio(with: theme.ink2)

            XCTAssertGreaterThanOrEqual(
                inkContrast,
                4.5,
                "\(theme.name) primary ink contrast \(inkContrast) must be >= 4.5:1"
            )
            XCTAssertGreaterThanOrEqual(
                secondaryContrast,
                4.5,
                "\(theme.name) secondary ink contrast \(secondaryContrast) must be >= 4.5:1"
            )
        }
    }

    func testResolvedThemeRespectsDarkPreference() {
        let light = PaperTheme.resolved(themeID: PaperTheme.cleanSheet.id, prefersDark: false)
        XCTAssertEqual(light.id, PaperTheme.cleanSheet.id)
        XCTAssertFalse(light.isDark)

        let dark = PaperTheme.resolved(themeID: PaperTheme.cleanSheet.id, prefersDark: true)
        XCTAssertEqual(dark.id, PaperTheme.graphite.id)
        XCTAssertTrue(dark.isDark)
    }

    func testLocalProEntitlementDefaultsToFalse() {
        UserDefaults.standard.removeObject(forKey: "debugOverrideProEntitlement")
        let entitlement = LocalProEntitlement()
        XCTAssertFalse(entitlement.isPro)
    }
}
