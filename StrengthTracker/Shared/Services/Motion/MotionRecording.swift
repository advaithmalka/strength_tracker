import Foundation

public struct LabeledMotionRecording: Codable, Sendable {
    public let exerciseID: UUID
    public let exerciseName: String
    public let wristSide: WristSide
    public let detectorVersion: String
    public let detectedReps: Int
    public let finalReps: Int
    public let samples: [MotionSample]
}

/// Explicit developer recording, kept on device for later detector evaluation.
@MainActor
public final class MotionRecording {
    private var samples: [MotionSample] = []
    private var exerciseID: UUID?
    private var exerciseName = ""
    private var detectorVersion = ""
    private var wristSide: WristSide = .left

    public init() {}

    public func begin(exerciseID: UUID, exerciseName: String, wristSide: WristSide,
                      detectorVersion: String, preRoll: [MotionSample]) {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "debugMotionRecordingEnabled") else { return }
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.wristSide = wristSide
        self.detectorVersion = detectorVersion
        self.samples = preRoll
        #endif
    }

    public func append(_ sample: MotionSample) {
        guard exerciseID != nil, samples.count < 30_000 else { return }
        samples.append(sample)
    }

    @discardableResult
    public func finish(detectedReps: Int, finalReps: Int) -> URL? {
        defer { exerciseID = nil; samples = [] }
        guard let exerciseID, !samples.isEmpty else { return nil }
        let recording = LabeledMotionRecording(
            exerciseID: exerciseID,
            exerciseName: exerciseName,
            wristSide: wristSide,
            detectorVersion: detectorVersion,
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
        exerciseID = nil
        samples = []
    }
}
