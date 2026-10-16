import Domain
import SwiftUI

/// One permission: name, live status, explanation, and the one action that
/// can change it.
struct PermissionRow: View {
    let permission: PermissionKind
    let model: PermissionsModel
    var showsExplanation = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(permission.displayName) {
                Text(status.displayName)
                    .foregroundStyle(status.isGranted ? .green : .secondary)
                    .accessibilityIdentifier("permission.\(permission.rawValue).status")
            }
            if showsExplanation {
                Text(permission.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let guidance = status.guidance {
                Text(guidance)
                    .font(.callout)
                    .accessibilityIdentifier("permission.\(permission.rawValue).guidance")
            }
            if let action = model.action(for: permission) {
                Button(action.title(for: permission)) {
                    Task { await model.perform(action, for: permission) }
                }
                .accessibilityIdentifier("permission.\(permission.rawValue).action")
            }
        }
    }

    private var status: PermissionStatus { model.status(for: permission) }
}

extension View {
    /// Re-reads permission state every second while the view is visible.
    /// Accessibility trust has no change notification, and the user changes it
    /// in System Settings while LemmeType is in the background.
    func pollsPermissions(_ model: PermissionsModel) -> some View {
        task {
            while !Task.isCancelled {
                model.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
