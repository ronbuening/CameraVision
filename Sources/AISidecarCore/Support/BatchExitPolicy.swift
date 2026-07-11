/// Stable process exit statuses for batch command outcomes.
///
/// A nil status means success (exit 0). Interrupted batches use the conventional
/// `128 + SIGINT` status and take precedence over ordinary per-file failures.
public enum BatchExitPolicy {
    public static let failureStatus: Int32 = 1
    public static let interruptedStatus: Int32 = 130

    public static func exitStatus(failureCount: Int, interrupted: Bool) -> Int32? {
        if interrupted {
            return interruptedStatus
        }
        return failureCount > 0 ? failureStatus : nil
    }
}
