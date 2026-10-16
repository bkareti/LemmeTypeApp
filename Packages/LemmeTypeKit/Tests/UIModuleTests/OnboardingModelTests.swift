import Domain
import TestSupport
import Testing

@testable import UI

@MainActor
struct OnboardingModelTests {
    private func makeModel(
        permissions: FakePermissions = FakePermissions(),
        preferences: FakePreferences = FakePreferences(),
        onFinish: @escaping @MainActor () -> Void = {}
    ) -> OnboardingModel {
        OnboardingModel(
            permissions: PermissionsModel(checker: permissions, requester: permissions),
            preferences: preferences,
            onFinish: onFinish
        )
    }

    @Test func noPromptAppearsBeforeItsExplanation() {
        let permissions = FakePermissions()
        let model = makeModel(permissions: permissions)

        #expect(model.step == .welcome)
        model.next()
        #expect(model.step == .microphone)
        model.next()
        #expect(model.step == .accessibility)

        #expect(permissions.microphoneRequestCount == 0)
        #expect(permissions.accessibilityRequestCount == 0)
    }

    @Test func stepsExplainOnePermissionEach() {
        #expect(OnboardingModel.Step.microphone.permission == .microphone)
        #expect(OnboardingModel.Step.accessibility.permission == .accessibility)
        #expect(OnboardingModel.Step.welcome.permission == nil)
        #expect(OnboardingModel.Step.summary.permission == nil)
    }

    @Test func canFinishInLimitedState() {
        let preferences = FakePreferences()
        var finished = false
        let model = makeModel(preferences: preferences, onFinish: { finished = true })

        model.next()
        model.next()
        model.next()
        #expect(model.step == .summary)
        #expect(model.isLimited)
        model.finish()

        #expect(finished)
        #expect(preferences.hasCompletedOnboarding)
    }

    @Test func notLimitedOnceEverythingIsGranted() {
        let model = makeModel(
            permissions: FakePermissions(statuses: [.microphone: .granted, .accessibility: .granted]))

        #expect(!model.isLimited)
    }

    @Test func backAndRestartNavigate() {
        let model = makeModel()
        model.next()
        model.next()

        model.back()
        #expect(model.step == .microphone)
        model.restart()
        #expect(model.step == .welcome)
        model.back()
        #expect(model.step == .welcome)
    }

    @Test func nextStopsAtSummary() {
        let model = makeModel()
        for _ in 0..<10 { model.next() }

        #expect(model.step == .summary)
    }
}
