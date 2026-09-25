import Foundation

public enum TemplateSeedData {
    private static func deterministicUUID(for name: String) -> UUID {
        var hash = [UInt8](repeating: 0, count: 16)
        for (index, byte) in name.utf8.enumerated() {
            let position = index % 16
            hash[position] = hash[position] &+ byte &+ UInt8(position)
        }
        for index in 0..<16 {
            hash[index] = hash[index] &+ hash[(index + 7) % 16]
        }
        return UUID(uuid: (
            hash[0], hash[1], hash[2], hash[3],
            hash[4], hash[5], hash[6], hash[7],
            hash[8], hash[9], hash[10], hash[11],
            hash[12], hash[13], hash[14], hash[15]
        ))
    }

    private static let exercisesByName = Dictionary(
        ExerciseSeedData.allExercises.map { ($0.name, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    private static func exercise(_ name: String) -> Exercise {
        guard let exercise = exercisesByName[name] else {
            fatalError("OneRep routine references unknown exercise: \(name)")
        }
        return exercise
    }

    private static func routine(_ name: String, order: Int, exerciseNames: [String]) -> WorkoutTemplate {
        WorkoutTemplate(
            id: deterministicUUID(for: "onerep:template:\(name)"),
            name: name,
            notes: nil,
            sortOrder: order,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: exerciseNames.enumerated().map { index, exerciseName in
                TemplateExercise(
                    id: deterministicUUID(for: "onerep:template:\(name):\(exerciseName)"),
                    exercise: exercise(exerciseName),
                    order: index,
                    supersetGroup: nil,
                    notes: nil,
                    restTimerSeconds: 150,
                    targetSets: 3,
                    targetReps: 10,
                    targetWeight: nil,
                    targetDurationSeconds: nil,
                    targetDistanceMeters: nil
                )
            },
            isCustom: true
        )
    }

    public static let allTemplates: [WorkoutTemplate] = [
        routine("Push", order: 0, exerciseNames: [
            "Incline Dumbbell Bench Press", "Pec Deck",
            "Straight-Bar Down-to-Up Tricep Extension", "Machine Shoulder Press",
            "Lateral Raise"
        ]),
        routine("Back", order: 1, exerciseNames: [
            "Lat Pulldown", "Upper-Back Row Machine", "Preacher Curl",
            "Trap Shrug", "Rope Bicep Curl", "Rear-Delt Fly"
        ]),
        routine("Legs", order: 2, exerciseNames: [
            "Leg Press", "Leg Curl", "Leg Extension", "Calf Raise"
        ])
    ]
}
