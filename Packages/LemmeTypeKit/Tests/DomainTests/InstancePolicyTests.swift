import Domain
import Foundation
import Testing

struct InstancePolicyTests {
    private let early = InstancePolicy.Instance(processIdentifier: 200, launchDate: Date(timeIntervalSince1970: 100))
    private let late = InstancePolicy.Instance(processIdentifier: 100, launchDate: Date(timeIntervalSince1970: 200))

    @Test func onlyInstanceKeepsRunning() {
        #expect(InstancePolicy.instanceToYieldTo(current: early, others: [early]) == nil)
    }

    @Test func laterLaunchYieldsToEarlierInstance() {
        #expect(InstancePolicy.instanceToYieldTo(current: late, others: [early, late]) == early)
    }

    @Test func earlierInstanceKeepsRunningWhenLaterOneAppears() {
        #expect(InstancePolicy.instanceToYieldTo(current: early, others: [early, late]) == nil)
    }

    @Test func simultaneousLaunchesResolveByProcessIdentifier() {
        let date = Date(timeIntervalSince1970: 100)
        let first = InstancePolicy.Instance(processIdentifier: 10, launchDate: date)
        let second = InstancePolicy.Instance(processIdentifier: 20, launchDate: date)

        #expect(InstancePolicy.instanceToYieldTo(current: second, others: [first, second]) == first)
        #expect(InstancePolicy.instanceToYieldTo(current: first, others: [first, second]) == nil)
    }

    @Test func yieldsToTheEarliestWhenSeveralAreRunning() {
        let middle = InstancePolicy.Instance(processIdentifier: 300, launchDate: Date(timeIntervalSince1970: 150))

        #expect(InstancePolicy.instanceToYieldTo(current: late, others: [middle, early, late]) == early)
    }
}
