#if canImport(ActivityKit)
@preconcurrency import ActivityKit
import Foundation
import StrengthTrackerShared

/// Mirrors the latest Watch-owned workout revision into one iPhone Live Activity.
/// WatchConnectivity remains the source of truth; this module only projects its
/// state into ActivityKit.
@MainActor
final class WatchWorkoutLiveActivityService {
    private var currentActivity: Activity<WatchWorkoutActivityAttributes>?

    func apply(_ liveState: WorkoutLiveState) async {
        guard liveState.phase != .ended, let workout = liveState.workout else {
            await end(sessionID: liveState.sessionID)
            return
        }

        let contentState = makeContentState(from: liveState, workout: workout)
        let content = ActivityContent(
            state: contentState,
            staleDate: liveState.phase == .resting ? liveState.restEndsAt : nil
        )

        if let activity = matchingActivity(sessionID: liveState.sessionID) {
            currentActivity = activity
            guard activity.content.state.revision < liveState.revision else { return }
            await activity.update(content)
            await endOtherActivities(keeping: activity.id)
            return
        }

        await endOtherActivities(keeping: nil)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = WatchWorkoutActivityAttributes(
            sessionID: liveState.sessionID,
            workoutName: workout.name,
            startedAt: workout.startedAt
        )

        do {
            currentActivity = try Activity.request(attributes: attributes, content: content)
        } catch {
            print("WatchWorkoutLiveActivityService: Failed to start Live Activity - \(error)")
        }
    }

    func endAll() async {
        await end(sessionID: nil)
    }

    private func matchingActivity(sessionID: UUID) -> Activity<WatchWorkoutActivityAttributes>? {
        if let currentActivity, currentActivity.attributes.sessionID == sessionID {
            return currentActivity
        }
        return Activity<WatchWorkoutActivityAttributes>.activities.first {
            $0.attributes.sessionID == sessionID
        }
    }

    private func end(sessionID: UUID?) async {
        let activities = Activity<WatchWorkoutActivityAttributes>.activities.filter {
            sessionID == nil || $0.attributes.sessionID == sessionID
        }
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        if sessionID == nil || currentActivity?.attributes.sessionID == sessionID {
            currentActivity = nil
        }
    }

    private func endOtherActivities(keeping activityID: String?) async {
        for activity in Activity<WatchWorkoutActivityAttributes>.activities where activity.id != activityID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func makeContentState(from state: WorkoutLiveState, workout: Workout) -> WatchWorkoutActivityAttributes.ContentState {
        let safeIndex = workout.exercises.indices.contains(state.currentExerciseIndex)
            ? state.currentExerciseIndex
            : 0
        let currentExercise = workout.exercises.indices.contains(safeIndex)
            ? workout.exercises[safeIndex]
            : nil
        let nextSet = currentExercise?.sets.first { !$0.isFullyCompleted }
        let completedSets = workout.exercises.reduce(0) { total, exercise in
            total + exercise.sets.filter(\.isFullyCompleted).count
        }

        return WatchWorkoutActivityAttributes.ContentState(
            revision: state.revision,
            phase: state.phase,
            exerciseName: currentExercise?.exercise.name ?? workout.name,
            exerciseNumber: workout.exercises.isEmpty ? 0 : safeIndex + 1,
            exerciseCount: workout.exercises.count,
            setNumber: nextSet?.order ?? currentExercise?.sets.count ?? 0,
            completedSets: completedSets,
            detectedReps: state.detectedReps,
            restEndsAt: state.restEndsAt,
            updatedAt: state.updatedAt
        )
    }
}
#endif
