import Foundation

public enum ExercisePeriodEvent: Sendable {
    case started
    case activity
}

/// Detects the boundaries of a set for any manually selected exercise.
/// This only detects a period of wrist movement; it does not infer the
/// exercise or count reps. Thresholds need calibration from Series 8 data.
public struct ExercisePeriodDetector: Sendable {
    private var recentActivity: [Bool] = []
    private var hasStarted = false

    public init() {}

    public mutating func reset() {
        recentActivity.removeAll(keepingCapacity: true)
        hasStarted = false
    }

    public mutating func process(_ sample: MotionSample) -> ExercisePeriodEvent? {
        let acceleration = sample.userAcceleration.magnitude
        let rotation = sample.rotationRate.magnitude
        let moving = acceleration >= 0.11 || rotation >= 0.8
        recentActivity.append(moving)
        if recentActivity.count > 25 { recentActivity.removeFirst() }

        if !hasStarted {
            guard recentActivity.count == 25,
                  recentActivity.filter({ $0 }).count >= 12 else { return nil }
            hasStarted = true
            return .started
        }
        return moving ? .activity : nil
    }
}
