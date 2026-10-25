import Foundation

/// How the app was launched. Sandbox mode is used for development and testing: only the
/// throwaway `RTEST-*` volumes are visible and the boot drive's Trash is never resolved.
public enum RuntimeMode: Sendable, Equatable {
    case live
    case sandbox

    /// Prefix of the throwaway test volumes created by `Scripts/sandbox.sh`.
    public static let sandboxVolumePrefix = "RTEST-"

    public static func detect(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> RuntimeMode {
        if arguments.contains("--sandbox") || environment["RECLAIM_SANDBOX"] == "1" {
            return .sandbox
        }
        return .live
    }
}
