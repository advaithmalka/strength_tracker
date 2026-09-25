# OneRep MVP

## Goal and device

Build an offline-capable strength logger for an Apple Watch Series 8 worn on the left wrist, with an iPhone companion. OneRep uses this repository's SwiftUI, SwiftData, HealthKit, and WatchConnectivity base. The first release supports manual exercise selection and automatic rep counting for one exercise. Automatic exercise recognition is a later release.

## Routines

The iPhone can edit routine order, exercise choices, target sets, target reps, and per-exercise rest duration. Three initial editable routines are:

| Routine | Initial exercise order |
| --- | --- |
| Push | Incline Dumbbell Press; Pec Deck; Straight-Bar Down-to-Up Tricep Extension; Machine Shoulder Press; Lateral Raise |
| Back | Lat Pulldown; Upper-Back Row Machine; Preacher Curl; Trap Shrug; Rope Bicep Curl; Rear-Delt Fly |
| Legs | Leg Press; Leg Curl; Leg Extension; Calf Raise |

Exercise names may be matched to built-in catalog entries or added as custom catalog entries. The Watch can swipe left or right through exercises in the active routine. This gesture changes the manually selected exercise in V1; a later classifier may use the same gesture to cycle through likely exercises by confidence. Legs remain fully loggable even without motion detection.

## Set flow

On the Watch, either a Start Set control or recognized movement begins an attempt for the selected exercise. A supported detector collects reps in the background; a generic/manual attempt works for every exercise. After a detected rep, five seconds without another detected rep ends the attempt. End Set ends it immediately. Both paths open a review showing detected reps, editable final reps, and editable weight. The Digital Crown scrolls normally outside focused fields; in a focused reps field it changes by one rep, and in a focused weight field it changes by 2.5 lb. Reps and weight are saved only after review. Detected and final reps are retained separately, including when the detector was unavailable and the set was entered manually.

The Watch begins a rest countdown after a set is saved. The default is 2:30, with a per-exercise override. Rest shows progress, haptics at completion, and can be ended early. Store actual set and rest timestamps/durations for future analysis.

## History and sync

Store workouts, exercise identity, set order, weight, detected reps, final reps, timestamps, and rest duration in SwiftData. The iPhone shows workout history, exercise history, and current mirrored workout state. Historical records must support future charts without requiring a data migration for basic weight/reps series; charts can follow later.

The Watch owns an active Watch-started workout. It saves every confirmed set locally, works without an iPhone connection, and queues completed workouts for reliable transfer. When reachable, it sends versioned snapshots with current exercise, set review/rest state, and revision. The iPhone can send active-workout controls while connected; the Watch acknowledges/rejects them against the current session and revision. Disconnected controls must not replay against a later set. Use WatchConnectivity rather than a raw Bluetooth link. Deduplicate completed-workout delivery by workout ID.

## Motion architecture

`MotionManager` owns CoreMotion sampling on Watch. `RepDetector` is a per-exercise interface that consumes timestamped, labeled motion samples and emits rep events. Begin with a left-wrist lateral raise detector, using an explicit start/finish state machine and conservative thresholding. Keep detector outputs separate from final user corrections. Developer recording is opt-in per attempt, stored locally with exercise label, wrist side, sample timestamps, detector version, and final count so future Create ML/Core ML activity classification can use it. Do not infer exercise identity in V1.

## Scope boundary

Keep the upstream AI chat, webhooks, and subscription controls hidden in OneRep V1. Do not add accounts, a cloud backend, social features, nutrition, coaching, or payments. Existing source for those features may remain temporarily to reduce migration risk; it is outside this MVP and must not run or transmit data through OneRep's normal workout flow.

## Delivery stages

1. **Logger foundation:** branding, seed routines, 2.5 lb/1 rep input, 2:30 rest, reliable Watch persistence, history, and exercise navigation.
2. **Session sync:** live Watch state envelope, phone controls with acknowledgement, offline catch-up, and session recovery.
3. **Rep detection:** CoreMotion service, lateral raise detector, five-second end review, manual override, and labeled debug recording.
4. **Later:** additional detectors, exercise recognition and confidence-ranked exercise cycling, charts, and detector calibration using corrected counts.
