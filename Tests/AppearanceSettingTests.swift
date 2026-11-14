import Testing
@testable import EishockeyGameCenter

@MainActor @Suite struct AppearanceSettingTests {
    @Test func pageIsDarkAccordingToTheSetting() {
        #expect(AppearanceSetting.system.isDark(systemIsDark: true))
        #expect(!AppearanceSetting.system.isDark(systemIsDark: false))
        #expect(AppearanceSetting.dark.isDark(systemIsDark: false))
        #expect(!AppearanceSetting.light.isDark(systemIsDark: true))
    }

    @Test func unknownStoredValueFallsBackToSystem() {
        #expect(AppearanceSetting(stored: "dark") == .dark)
        #expect(AppearanceSetting(stored: "") == .system)
        #expect(AppearanceSetting(stored: "sepia") == .system)
    }
}
