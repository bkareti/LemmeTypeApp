import Domain
import SwiftUI

public struct OnboardingView: View {
    private let model: OnboardingModel

    public init(model: OnboardingModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack {
                if model.step != .welcome {
                    Button(String(localized: "Back", bundle: .module)) { model.back() }
                }
                Spacer()
                primaryButton
            }
        }
        .padding(24)
        .frame(width: 480, height: 340)
        .pollsPermissions(model.permissions)
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .welcome:
            Text(String(localized: "Welcome to LemmeType", bundle: .module))
                .font(.title)
                .accessibilityIdentifier("onboarding.title")
            Text(
                String(
                    localized: """
                        Speak naturally and LemmeType writes the text into whatever app you're using. \
                        Setup takes two permissions. You'll see why each is needed before macOS asks.
                        """,
                    bundle: .module
                ))
        case .microphone, .accessibility:
            if let permission = model.step.permission {
                Text(permission.displayName)
                    .font(.title)
                    .accessibilityIdentifier("onboarding.title")
                PermissionRow(permission: permission, model: model.permissions)
            }
        case .summary:
            Text(String(localized: "Setup summary", bundle: .module))
                .font(.title)
                .accessibilityIdentifier("onboarding.title")
            ForEach(PermissionKind.allCases, id: \.self) { permission in
                PermissionRow(permission: permission, model: model.permissions, showsExplanation: false)
            }
            if model.isLimited {
                Text(
                    String(
                        localized: """
                            Some features stay unavailable until the missing permissions are granted. \
                            You can finish this any time from the LemmeType menu.
                            """,
                        bundle: .module
                    )
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("onboarding.limitedNote")
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if model.step == .summary {
            Button(String(localized: "Done", bundle: .module)) { model.finish() }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding.done")
        } else {
            let isPermissionPending =
                model.step.permission.map { !model.permissions.status(for: $0).isGranted } ?? false
            Button(
                isPermissionPending
                    ? String(localized: "Not Now", bundle: .module)
                    : String(localized: "Continue", bundle: .module)
            ) { model.next() }
            .keyboardShortcut(isPermissionPending ? .cancelAction : .defaultAction)
            .accessibilityIdentifier("onboarding.next")
        }
    }
}
