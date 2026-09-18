import Testing
@testable import TartKit

@Suite struct VMResourceValidatorTests {
    let host = HostFacts(memoryBytes: 16 * 1024 * 1024 * 1024, coreCount: 8)

    func fields(cpu: String = "", memory: String = "", disk: String = "",
                display: String = "", refit: Bool? = nil) -> ResourceEditorFields {
        ResourceEditorFields(cpuText: cpu, memoryText: memory, diskText: disk,
                             displayText: display, displayRefit: refit)
    }

    @Test func growOnlyDiskRefusesSmallerValue() {
        let result = VMResourceValidator.validate(fields: fields(disk: "30"),
                                                  currentDiskGB: 60, host: host)
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.contains("only grow") })
        #expect(result.warnings.isEmpty)
    }

    @Test func allowedDiskAtOrAboveRoundedCurrent() {
        let same = VMResourceValidator.validate(fields: fields(disk: "60"),
                                                currentDiskGB: 60, host: host)
        let bigger = VMResourceValidator.validate(fields: fields(disk: "120"),
                                                  currentDiskGB: 60, host: host)
        #expect(same.isValid)
        #expect(bigger.isValid)
    }

    @Test func diskComparisonUsesTheSameRoundingTheEditorDisplays() {
        // The editor shows Int(79.4.rounded()) = 79; the validator must
        // compare against the same rounding so re-applying the shown value
        // never trips grow-only (finding 8).
        let a = VMResourceValidator.validate(fields: fields(disk: "79"),
                                             currentDiskGB: 79.4, host: host)
        #expect(a.isValid)
        let b = VMResourceValidator.validate(fields: fields(disk: "80"),
                                             currentDiskGB: 79.9, host: host)
        #expect(b.isValid)
        let c = VMResourceValidator.validate(fields: fields(disk: "78"),
                                             currentDiskGB: 79.4, host: host)
        #expect(!c.isValid)
    }

    @Test func malformedNonIntegerTextIsAHardError() {
        // "abc" must become an inline error that disables Apply, not a
        // silently-dropped field (finding 1).
        let badCPU = VMResourceValidator.validate(fields: fields(cpu: "abc"),
                                                  currentDiskGB: 0, host: host)
        #expect(!badCPU.isValid)
        #expect(badCPU.errors.contains { $0.contains("whole number") })

        let badMemory = VMResourceValidator.validate(fields: fields(memory: "abc"),
                                                     currentDiskGB: 0, host: host)
        #expect(!badMemory.isValid)

        let badDisk = VMResourceValidator.validate(fields: fields(disk: "abc"),
                                                   currentDiskGB: 0, host: host)
        #expect(!badDisk.isValid)
    }

    @Test func zeroAndNegativeValuesAreHardErrors() {
        #expect(!VMResourceValidator.validate(fields: fields(cpu: "0"),
                                              currentDiskGB: 0, host: host).isValid)
        #expect(!VMResourceValidator.validate(fields: fields(memory: "0"),
                                              currentDiskGB: 0, host: host).isValid)
        #expect(!VMResourceValidator.validate(fields: fields(disk: "0"),
                                              currentDiskGB: 0, host: host).isValid)
    }

    @Test func malformedDisplayIsAHardError() {
        #expect(!VMResourceValidator.validate(fields: fields(display: "big"),
                                              currentDiskGB: 0, host: host).isValid)
        #expect(!VMResourceValidator.validate(fields: fields(display: "0x0"),
                                              currentDiskGB: 0, host: host).isValid)
    }

    @Test func displayFormatAcceptsTrailingUnits() {
        #expect(VMResourceValidator.validate(fields: fields(display: "1200x800pt"),
                                             currentDiskGB: 0, host: host).isValid)
    }

    @Test func allErrorsAccumulate() {
        // A grow-only violation plus a bad display plus malformed CPU must
        // report every error, not just the first (finding 10).
        let result = VMResourceValidator.validate(
            fields: fields(cpu: "abc", disk: "30", display: "big"),
            currentDiskGB: 60, host: host)
        #expect(!result.isValid)
        #expect(result.errors.count == 3)
    }

    @Test func softWarningsUseHostFacts() {
        let lowResult = VMResourceValidator.validate(fields: fields(memory: "4096"),
                                                     currentDiskGB: 0, host: host)
        #expect(lowResult.isValid)
        #expect(lowResult.warnings.contains { $0.contains("8 GB") })

        let overResult = VMResourceValidator.validate(fields: fields(memory: "32768"),
                                                      currentDiskGB: 0, host: host)
        #expect(overResult.isValid)
        #expect(overResult.warnings.contains { $0.contains("physical RAM") })

        let nearResult = VMResourceValidator.validate(fields: fields(memory: "15360"),
                                                      currentDiskGB: 0, host: host)
        #expect(nearResult.warnings.contains { $0.contains("within 10%") })

        let cpuResult = VMResourceValidator.validate(fields: fields(cpu: "12"),
                                                     currentDiskGB: 0, host: host)
        #expect(cpuResult.warnings.contains { $0.contains("cores") })
    }

    @Test func ampleValuesProduceNothing() {
        let result = VMResourceValidator.validate(
            fields: fields(cpu: "4", memory: "8192", disk: "80", display: "1200x800"),
            currentDiskGB: 40, host: host)
        #expect(result.isValid)
        #expect(result.warnings.isEmpty)
    }

    @Test func emptyDraftValidatesWithoutErrors() {
        let result = VMResourceValidator.validate(fields: fields(),
                                                  currentDiskGB: 40, host: host)
        #expect(result.isValid)
        #expect(result.errors.isEmpty)
    }
}
