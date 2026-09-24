import IOKit.pwr_mgt

final class ViewerPowerAssertion {
    private var assertionIDs: [IOPMAssertionID] = []

    func acquire() {
        guard assertionIDs.isEmpty else {
            return
        }

        let assertionTypes = [
            kIOPMAssertionTypePreventUserIdleSystemSleep,
            kIOPMAssertionTypePreventUserIdleDisplaySleep
        ]

        for assertionType in assertionTypes {
            var assertionID = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                assertionType as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "DroidHatch video viewer" as CFString,
                &assertionID)
            if result == kIOReturnSuccess {
                assertionIDs.append(assertionID)
            }
        }
    }

    func release() {
        for assertionID in assertionIDs {
            IOPMAssertionRelease(assertionID)
        }
        assertionIDs.removeAll(keepingCapacity: true)
    }

    deinit {
        release()
    }
}
