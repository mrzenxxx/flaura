import Testing
@testable import AuraCore

/// The rule: lights follow the monitor. On while any display is on (desktop, lock screen,
/// login form), off once displays sleep or the Mac sleeps.
@Suite struct PowerStateTests {
    @Test func lockScreenWithDisplayOnKeepsLightsOn() {
        let state = PowerState(displaysAsleep: false, locked: true, systemAsleep: false)
        #expect(!state.shouldSuspend(dimWhenIdle: true))
    }

    @Test func displaySleepTurnsLightsOff() {
        #expect(PowerState(displaysAsleep: true, locked: false, systemAsleep: false).shouldSuspend(dimWhenIdle: true))
        #expect(PowerState(displaysAsleep: true, locked: true, systemAsleep: false).shouldSuspend(dimWhenIdle: true))
    }

    @Test func wakingToTheLockScreenTurnsLightsBackOn() {
        var state = PowerState(displaysAsleep: true, locked: true, systemAsleep: false)
        #expect(state.shouldSuspend(dimWhenIdle: true))
        state.displaysAsleep = false
        #expect(!state.shouldSuspend(dimWhenIdle: true))
    }

    @Test func systemSleepAlwaysSuspends() {
        let state = PowerState(displaysAsleep: false, locked: false, systemAsleep: true)
        #expect(state.shouldSuspend(dimWhenIdle: false))
        #expect(state.shouldSuspend(dimWhenIdle: true))
    }

    @Test func withoutDimmingDisplaySleepKeepsRendering() {
        let state = PowerState(displaysAsleep: true, locked: true, systemAsleep: false)
        #expect(!state.shouldSuspend(dimWhenIdle: false))
    }

    @Test func awakeAndUnlockedRenders() {
        #expect(!PowerState().shouldSuspend(dimWhenIdle: true))
    }
}
