import Foundation

/// Lightweight state for sharing rest timer info from the watch app to the
/// native watchOS widget via App Group UserDefaults.
public struct WatchRestTimerState: Codable, Sendable {
    public let exerciseName: String
    public let setNumber: Int
    public let startDate: Date
    public let endDate: Date
    public let totalSeconds: Int
    public let workoutID: UUID?
    public let setID: UUID?

    public static let userDefaultsKey = "watch_rest_timer_state"

    public init(exerciseName: String, setNumber: Int, startDate: Date, endDate: Date,
                totalSeconds: Int, workoutID: UUID? = nil, setID: UUID? = nil) {
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.startDate = startDate
        self.endDate = endDate
        self.totalSeconds = totalSeconds
        self.workoutID = workoutID
        self.setID = setID
    }
}
