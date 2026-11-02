#if os(iOS)
    import SwiftUI

    /// The iPhone and iPad app: Dictate and Settings, as tabs on a phone and a
    /// sidebar on an iPad (E8-S9). The app-switcher snapshot is covered so a
    /// result on screen is never shown there, and a recording stops when the app
    /// goes to the background (E8-S4).
    public struct MobileRootView: View {
        enum Tab: Hashable {
            case dictate
            case settings
        }

        let quick: QuickDictationModel
        let settings: MobileSettingsView
        let dictation: DictationSettingsModel
        @State private var tab: Tab = .dictate
        @Environment(\.scenePhase) private var scenePhase

        public init(quick: QuickDictationModel, dictation: DictationSettingsModel, settings: MobileSettingsView) {
            self.quick = quick
            self.dictation = dictation
            self.settings = settings
        }

        public var body: some View {
            TabView(selection: $tab) {
                SwiftUI.Tab(String(localized: "Dictate", bundle: .module), systemImage: "mic.fill", value: Tab.dictate)
                {
                    NavigationStack {
                        QuickDictationView(model: quick, dictation: dictation) { tab = .settings }
                    }
                }
                SwiftUI.Tab(
                    String(localized: "Settings", bundle: .module), systemImage: "gearshape", value: Tab.settings
                ) {
                    NavigationStack { settings }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .overlay {
                if scenePhase != .active { PrivacyCover() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { quick.recorder.stopForSystemReason() }
                if phase == .active { quick.startIfRequestedByShortcut() }
            }
            .task { quick.recorder.onOpenSettings = { _ in tab = .settings } }
        }
    }

    /// Hides the screen while the app is not active, so the app switcher never shows a result.
    struct PrivacyCover: View {
        var body: some View {
            ZStack {
                Rectangle().fill(.background)
                Image(systemName: "mic.fill").font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
#endif
