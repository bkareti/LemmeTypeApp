import Testing

@testable import UI

/// E7-S6: ⌃Tab and ⌃⇧Tab move through the panes in tab-bar order and wrap.
@MainActor
struct SettingsNavigationTests {
    @Test func nextVisitsEveryPaneInOrderAndWraps() {
        let navigation = SettingsNavigation()
        var visited: [SettingsNavigation.Pane] = [navigation.selectedPane]
        for _ in SettingsNavigation.order.dropFirst() {
            navigation.selectNext()
            visited.append(navigation.selectedPane)
        }
        #expect(visited == SettingsNavigation.order)
        navigation.selectNext()
        #expect(navigation.selectedPane == .general)
    }

    @Test func previousWrapsFromTheFirstPaneToTheLast() {
        let navigation = SettingsNavigation()
        navigation.selectPrevious()
        #expect(navigation.selectedPane == .diagnostics)
        navigation.selectPrevious()
        #expect(navigation.selectedPane == .privacy)
    }
}
