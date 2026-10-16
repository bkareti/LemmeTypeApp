import Domain

/// Interim delivery until Accessibility insertion (E2-S7): copies the text so
/// the user can paste it, and reports `.copied`.
public struct CopyingTextDelivery: TextDelivering {
    private let copier: any TextCopying

    public init(copier: any TextCopying) {
        self.copier = copier
    }

    public func deliver(_ text: String, to target: ActivationTarget?) async -> DeliveryOutcome {
        await copier.copy(text)
        return .delivered(.copied)
    }
}
