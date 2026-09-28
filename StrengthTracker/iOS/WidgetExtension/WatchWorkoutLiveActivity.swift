#if canImport(ActivityKit)
import ActivityKit
import StrengthTrackerShared
import SwiftUI
import WidgetKit

struct WatchWorkoutLiveActivity: Widget {
    private static let accent = Color(red: 0.149, green: 0.475, blue: 1.000)
    private static let deepLink = URL(string: "onerep://workout")!

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WatchWorkoutActivityAttributes.self) { context in
            WatchWorkoutLockScreenView(context: context)
                .activityBackgroundTint(Color(red: 0.071, green: 0.071, blue: 0.071))
                .widgetURL(Self.deepLink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("WATCH", systemImage: "applewatch")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Self.accent)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    phaseDetail(context.state)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Self.accent)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(context.state.exerciseName)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        HStack {
                            Text("Exercise \(context.state.exerciseNumber) of \(context.state.exerciseCount)")
                            Spacer()
                            Text("\(context.state.completedSets) sets done")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "applewatch")
                    .foregroundStyle(Self.accent)
            } compactTrailing: {
                compactDetail(context.state)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Self.accent)
            } minimal: {
                Image(systemName: context.state.phase == .resting ? "timer" : "dumbbell.fill")
                    .foregroundStyle(Self.accent)
            }
            .widgetURL(Self.deepLink)
        }
    }

    @ViewBuilder
    private func phaseDetail(_ state: WatchWorkoutActivityAttributes.ContentState) -> some View {
        if state.phase == .resting, let end = state.restEndsAt, end > Date() {
            Text(timerInterval: Date()...end, countsDown: true).monospacedDigit()
        } else if state.phase == .lifting, let reps = state.detectedReps {
            Text("\(reps) reps")
        } else {
            Text(state.phase.label)
        }
    }

    @ViewBuilder
    private func compactDetail(_ state: WatchWorkoutActivityAttributes.ContentState) -> some View {
        if state.phase == .resting, let end = state.restEndsAt, end > Date() {
            Text(timerInterval: Date()...end, countsDown: true).monospacedDigit()
        } else if state.phase == .lifting, let reps = state.detectedReps {
            Text("\(reps)")
        } else {
            Text("S\(state.setNumber)")
        }
    }
}

private struct WatchWorkoutLockScreenView: View {
    let context: ActivityViewContext<WatchWorkoutActivityAttributes>
    private static let accent = Color(red: 0.149, green: 0.475, blue: 1.000)

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "applewatch")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(Self.accent)
                .frame(width: 42, height: 42)
                .background(Self.accent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.workoutName.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(context.state.exerciseName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Set \(context.state.setNumber) · \(context.state.completedSets) completed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            status
                .foregroundStyle(Self.accent)
        }
        .padding(16)
    }

    @ViewBuilder
    private var status: some View {
        if context.state.phase == .resting,
           let end = context.state.restEndsAt,
           end > Date() {
            VStack(alignment: .trailing, spacing: 2) {
                Text("REST").font(.system(size: 9, weight: .bold)).tracking(1)
                Text(timerInterval: Date()...end, countsDown: true)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
        } else if context.state.phase == .lifting {
            VStack(alignment: .trailing, spacing: 2) {
                Text("LIFTING").font(.system(size: 9, weight: .bold)).tracking(1)
                Text(context.state.detectedReps.map { "\($0) reps" } ?? "Active")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
        } else {
            Text(context.state.phase.label)
                .font(.system(size: 13, weight: .bold))
        }
    }
}

private extension WorkoutLivePhase {
    var label: String {
        switch self {
        case .ready: "READY"
        case .lifting: "LIFTING"
        case .review: "REVIEW"
        case .resting: "REST"
        case .ended: "DONE"
        }
    }
}
#endif
