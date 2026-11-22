import XCTest
@testable import VoiceTypeTests

final class PaperThemeTests: XCTestCase {
    func testAllNineThemesMeetMinimumWCAGContrast() {
        XCTAssertEqual(PaperTheme.allThemes.count, 9)

        for theme in PaperTheme.allThemes {
            let inkContrast = theme.base.contrastRatio(with: theme.ink)
            let secondaryContrast = theme.base.contrastRatio(with: theme.ink2)

            print(String(format: "[Contrast] %@ (%@): ink=%.2f:1, ink2=%.2f:1",
                         theme.name, theme.id, inkContrast, secondaryContrast))

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

    func testProceduralTileGenerationProduces512x512ForAllTexturedPapers() {
        let textured = PaperTheme.allThemes.compactMap { $0.texture as? ProceduralPaperTexture }
        XCTAssertEqual(textured.count, 8)

        for tex in textured {
            let image = PaperTextureCache.shared.generateTile(for: tex)
            XCTAssertNotNil(image, "Tile must generate for \(tex.id)")
            XCTAssertEqual(image?.size.width ?? 0, 512, accuracy: 0.1)
            XCTAssertEqual(image?.size.height ?? 0, 512, accuracy: 0.1)
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
