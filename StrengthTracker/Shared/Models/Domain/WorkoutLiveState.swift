import Foundation

public enum WorkoutLivePhase: String, Codable, Sendable {
    case ready, lifting, review, resting, ended
}

/// Latest Watch-owned session state. A nil workout is an end-of-session
/// tombstone so the phone can clear an offline mirror when it reconnects.
public struct WorkoutLiveState: Codable, Sendable {
    public let schemaVersion: Int
    public let sessionID: UUID
    public let revision: Int64
    public let updatedAt: Date
    public let workout: Workout?
    public let currentExerciseIndex: Int
    public let phase: WorkoutLivePhase
    public let detectedReps: Int?
    public let restEndsAt: Date?

    public init(sessionID: UUID, revision: Int64, workout: Workout?,
                currentExerciseIndex: Int, phase: WorkoutLivePhase,
                detectedReps: Int?, restEndsAt: Date?) {
        self.schemaVersion = 1
        self.sessionID = sessionID
        self.revision = revision
        self.updatedAt = Date()
        self.workout = workout
        self.currentExerciseIndex = currentExerciseIndex
        self.phase = phase
        self.detectedReps = detectedReps
        self.restEndsAt = restEndsAt
    }
}

public enum WorkoutLiveAction: String, Codable, Sendable {
    case startSet, endSet, nextExercise, previousExercise, skipRest
}

public struct WorkoutLiveCommand: Codable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let expectedRevision: Int64
    public let action: WorkoutLiveAction

    public init(sessionID: UUID, expectedRevision: Int64, action: WorkoutLiveAction) {
        self.id = UUID()
        self.sessionID = sessionID
        self.expectedRevision = expectedRevision
        self.action = action
    }
}

public struct WorkoutLiveCommandReply: Codable, Sendable {
    public let accepted: Bool
    public let reason: String?

    public init(accepted: Bool, reason: String? = nil) {
        self.accepted = accepted
        self.reason = reason
    }
}
