import Foundation

/// Initial left-wrist detector. Gravity angle is relative to a resting arm
/// baseline; a rep requires a raised phase followed by a controlled return.
/// Thresholds are provisional until real Series 8 recordings are calibrated.
public struct LateralRaiseRepDetector: RepDetector {
    public let version = "lateral-raise-left-1"

    private enum Phase { case lowered, raised(Date) }
    private var phase: Phase = .lowered
    private var restingGravity: MotionVector3?
    private var lastRepAt: Date?

    public init() {}

    public mutating func reset() {
        phase = .lowered
        restingGravity = nil
        lastRepAt = nil
    }

    public mutating func process(_ sample: MotionSample) -> RepDetectorEvent? {
        guard sample.wristSide == .left else { return nil }
        guard let baseline = restingGravity else {
            restingGravity = sample.gravity
            return nil
        }
        let denominator = max(0.0001, baseline.magnitude * sample.gravity.magnitude)
        let cosine = min(1, max(-1, baseline.dot(sample.gravity) / denominator))
        let angle = acos(cosine) * 180 / .pi

        switch phase {
        case .lowered:
            if angle < 12 {
                restingGravity = MotionVector3(
                    x: baseline.x * 0.97 + sample.gravity.x * 0.03,
                    y: baseline.y * 0.97 + sample.gravity.y * 0.03,
                    z: baseline.z * 0.97 + sample.gravity.z * 0.03
                )
            }
            guard angle >= 35,
                  lastRepAt.map({ sample.recordedAt.timeIntervalSince($0) >= 0.5 }) ?? true else { return nil }
            phase = .raised(sample.recordedAt)
            return .movementStarted
        case .raised(let raisedAt):
            guard angle <= 18, sample.recordedAt.timeIntervalSince(raisedAt) >= 0.35 else { return nil }
            phase = .lowered
            lastRepAt = sample.recordedAt
            return .repCompleted(confidence: 0.5)
        }
    }
}
