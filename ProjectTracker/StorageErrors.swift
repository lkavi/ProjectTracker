import Foundation
import Observation

/// One storage failure worth telling the user about.
struct StorageFailure: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

/// Collects file-system failures from the stores so the UI can surface them.
/// The stores keep their fire-and-forget call sites; instead of swallowing an
/// error with `try?` they report it here, and ContentView shows one alert.
@MainActor
@Observable
final class StorageErrors {
    static let shared = StorageErrors()

    /// The failure waiting to be shown. Only the first of a burst is kept
    /// until the user dismisses it, so a cascade of errors is one alert.
    var pending: StorageFailure?

    /// - Parameters:
    ///   - failedAction: what could not be done, e.g. "save the project".
    ///   - error: the underlying error; its description is shown verbatim.
    func report(_ failedAction: String, error: Error) {
        print("[ProjectTracker] ❌ Couldn't \(failedAction): \(error.localizedDescription)")
        guard pending == nil else { return }
        pending = StorageFailure(message:
            "Couldn't \(failedAction). \(error.localizedDescription) "
            + "Your latest change may not be stored. Check free space and "
            + "iCloud Drive access, then try again.")
    }
}
