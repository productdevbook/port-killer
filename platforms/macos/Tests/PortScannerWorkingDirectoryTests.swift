import Foundation
import Testing
@testable import PortKiller

/**
 * Tests for working-directory detection via proc_pidinfo.
 */
struct PortScannerWorkingDirectoryTests {

    @Test("Reads the current process's working directory")
    func ownProcessWorkingDirectory() {
        let cwd = PortScanner.workingDirectory(for: Int(ProcessInfo.processInfo.processIdentifier))
        #expect(cwd == FileManager.default.currentDirectoryPath)
    }

    @Test("Returns nil for another user's process")
    func rootProcessReturnsNil() {
        // launchd (pid 1) is root-owned; unprivileged callers get no access
        #expect(PortScanner.workingDirectory(for: 1) == nil)
    }

    @Test("Returns nil for an invalid PID")
    func invalidPidReturnsNil() {
        #expect(PortScanner.workingDirectory(for: 99_999_999) == nil)
    }
}
