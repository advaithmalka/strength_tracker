#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// The compact, presentation-ready state shown by the iPhone while a workout
/// is owned and recorded by the paired Apple Watch.
public struct WatchWorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var revision: Int64
        public var phase: WorkoutLivePhase
        public var exerciseName: String
        public var exerciseNumber: Int
        public var exerciseCount: Int
        public var setNumber: Int
        public var completedSets: Int
        public var detectedReps: Int?
        public var restEndsAt: Date?
        public var updatedAt: Date

        public init(
            revision: Int64,
            phase: WorkoutLivePhase,
            exerciseName: String,
            exerciseNumber: Int,
            exerciseCount: Int,
            setNumber: Int,
            completedSets: Int,
            detectedReps: Int?,
            restEndsAt: Date?,
            updatedAt: Date
        ) {
            self.revision = revision
            self.phase = phase
            self.exerciseName = exerciseName
            self.exerciseNumber = exerciseNumber
            self.exerciseCount = exerciseCount
            self.setNumber = setNumber
            self.completedSets = completedSets
            self.detectedReps = detectedReps
            self.restEndsAt = restEndsAt
            self.updatedAt = updatedAt
        }
    }

    public var sessionID: UUID
    public var workoutName: String
    public var startedAt: Date

    public init(sessionID: UUID, workoutName: String, startedAt: Date) {
        self.sessionID = sessionID
        self.workoutName = workoutName
        self.startedAt = startedAt
    }
}
#endif
