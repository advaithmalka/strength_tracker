import Foundation

public struct LabeledMotionRecording: Codable, Sendable {
    /// Optional so recordings written before schema version 2 remain decodable.
    public let workoutID: UUID?
    public let workoutExerciseID: UUID?
    public let setID: UUID?
    public let setNumber: Int?
    public let exerciseID: UUID
    public let exerciseName: String
    public let wristSide: WristSide
    public let detectorVersion: String
    public let detectedReps: Int
    public let finalReps: Int
    public let samples: [MotionSample]
}

public struct MotionRecordingContext: Sendable {
    public let workoutID: UUID
    public let workoutExerciseID: UUID
    public let setID: UUID
    public let setNumber: Int
    public let exerciseID: UUID
    public let exerciseName: String
    public let wristSide: WristSide
    public let detectorVersion: String

    public init(workoutID: UUID, workoutExerciseID: UUID, setID: UUID, setNumber: Int,
                exerciseID: UUID, exerciseName: String, wristSide: WristSide,
                detectorVersion: String) {
        self.workoutID = workoutID
        self.workoutExerciseID = workoutExerciseID
        self.setID = setID
        self.setNumber = setNumber
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.wristSide = wristSide
        self.detectorVersion = detectorVersion
    }
}

/// Explicit developer recording, kept on device for later detector evaluation.
@MainActor
public final class MotionRecording {
    private var samples: [MotionSample] = []
    private var context: MotionRecordingContext?

    public init() {}

    public func begin(context: MotionRecordingContext, preRoll: [MotionSample]) {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "debugMotionRecordingEnabled") else { return }
        self.context = context
        self.samples = preRoll
        #endif
    }

    public func append(_ sample: MotionSample) {
        guard context != nil, samples.count < 30_000 else { return }
        samples.append(sample)
    }

    @discardableResult
    public func finish(detectedReps: Int, finalReps: Int) -> URL? {
        defer { context = nil; samples = [] }
        guard let context, !samples.isEmpty else { return nil }
        let recording = LabeledMotionRecording(
            workoutID: context.workoutID,
            workoutExerciseID: context.workoutExerciseID,
            setID: context.setID,
            setNumber: context.setNumber,
            exerciseID: context.exerciseID,
            exerciseName: context.exerciseName,
            wristSide: context.wristSide,
            detectorVersion: context.detectorVersion,
            detectedReps: detectedReps,
            finalReps: finalReps,
            samples: samples
        )
        do {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let directory = documents.appendingPathComponent("MotionRecordings", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(UUID().uuidString).json")
            try JSONEncoder().encode(recording).write(to: url, options: .atomic)
            return url
        } catch {
            print("[MotionRecording] Save failed: \(error)")
            return nil
        }
    }

    public func discard() {
        context = nil
        samples = []
    }
}
