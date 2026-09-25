import Foundation

public enum WristSide: String, Codable, Sendable {
    case left, right
}

public struct MotionVector3: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public var magnitude: Double { (x * x + y * y + z * z).squareRoot() }
    public func dot(_ other: Self) -> Double { x * other.x + y * other.y + z * other.z }
}

/// A labeled Watch sample. The label is selected by the lifter in V1.
public struct MotionSample: Codable, Hashable, Sendable {
    public let recordedAt: Date
    public let exerciseID: UUID
    public let wristSide: WristSide
    public let gravity: MotionVector3
    public let userAcceleration: MotionVector3
    public let rotationRate: MotionVector3

    public init(recordedAt: Date, exerciseID: UUID, wristSide: WristSide,
                gravity: MotionVector3, userAcceleration: MotionVector3,
                rotationRate: MotionVector3) {
        self.recordedAt = recordedAt
        self.exerciseID = exerciseID
        self.wristSide = wristSide
        self.gravity = gravity
        self.userAcceleration = userAcceleration
        self.rotationRate = rotationRate
    }
}

public enum RepDetectorEvent: Sendable {
    case movementStarted
    case repCompleted(confidence: Double)
}

/// Each exercise owns its own movement pattern and calibration.
public protocol RepDetector: Sendable {
    var version: String { get }
    mutating func process(_ sample: MotionSample) -> RepDetectorEvent?
    mutating func reset()
}

public enum RepDetectorFactory {
    public static func make(exerciseName: String, wristSide: WristSide) -> (any RepDetector)? {
        guard wristSide == .left else { return nil }
        switch exerciseName {
        case "Lateral Raise": return LateralRaiseRepDetector()
        default: return nil
        }
    }
}
