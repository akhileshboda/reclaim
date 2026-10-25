import Foundation
import os
import ReclaimCore

/// Turns errors into plain-language messages with a next step. Technical detail (paths, error
/// codes) goes to the unified log, not the screen.
enum UserMessage {
    static let log = Logger(subsystem: "com.akhileshboda.reclaim", category: "actions")

    static func describe(_ error: any Error, driveName: String) -> String {
        log.error("\(driveName, privacy: .public): \(String(describing: error), privacy: .public)")
        switch error {
        case SafetyPolicy.Violation.notAllowedInSandbox:
            return "“\(driveName)” isn’t a test drive, so sandbox mode left it alone."
        case SafetyPolicy.Violation.notAVolume:
            return "Reclaim only removes hidden files from external drives."
        case is SafetyPolicy.Violation:
            return "Nothing was erased on “\(driveName)” because its Trash isn’t where macOS normally keeps it. Use Finder to empty it."
        case JunkScanner.ScanError.timeMachineVolume:
            return "“\(driveName)” is a Time Machine backup drive, so Reclaim leaves it alone."
        case JunkScanner.ScanError.unreadable:
            return "Reclaim couldn’t read “\(driveName)”. Make sure it’s still connected, and that Reclaim may access removable volumes in Privacy & Security settings."
        case let error as POSIXError where error.code == .EPERM || error.code == .EACCES:
            return "Reclaim isn’t allowed to read the Trash on “\(driveName)”. Check Full Disk Access in Privacy & Security settings."
        case let error as POSIXError where error.code == .ENOENT || error.code == .ENXIO || error.code == .EIO:
            return "“\(driveName)” stopped responding. It may have been disconnected."
        default:
            return (error as NSError).localizedDescription
        }
    }
}
