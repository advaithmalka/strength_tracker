# OneRep: first exercise recognition model for Push and Back

Research date: 2026-09-26

## Recommendation

Build a **small, on-device exercise classifier as V2**, after collecting Watch recordings. Do not replace the current V1 detector with an 11-class CNN immediately: the repository has a useful heuristic detector for left-wrist lateral raises, but no OneRep-trained model or training set yet. Keep that detector and manual exercise selection as the fallback.

Train the first experiment in Python/PyTorch and convert it to Core ML for Watch inference. Compare a compact 1D CNN against a classical feature-based baseline (SVM or Random Forest). Exercise recognition from one wrist sensor is feasible in research, but the published numbers vary substantially with dataset and task; they are not a forecast of OneRep's accuracy.

Treat the first two workouts as **personal calibration**, not as enough data to train a neural network from scratch. A general model must first be trained across many lifters. During two labeled workouts, freeze its feature extractor and collect user-specific window embeddings for each exercise. Then test a small, regularized per-user classifier or a blend of global class scores with per-user class prototypes. Do not personalize a class until it has enough clean examples; otherwise keep the global model and manual choice. If the intended onboarding has one Push and one Back workout, this can calibrate all eleven only when the user actually performs and confirms all eleven.

## The eleven target classes in the app

The canonical routine seed in `StrengthTracker/Shared/Services/TemplateSeedData.swift` lists these labels. Push has five and Back has six:

| Routine | Class label |
|---|---|
| Push | Incline Dumbbell Bench Press |
| Push | Pec Deck |
| Push | Straight-Bar Down-to-Up Tricep Extension |
| Push | Machine Shoulder Press |
| Push | Lateral Raise |
| Back | Lat Pulldown |
| Back | Upper-Back Row Machine |
| Back | Preacher Curl |
| Back | Trap Shrug |
| Back | Rope Bicep Curl |
| Back | Rear-Delt Fly |

Keep the exact exercise ID/name mapping in app data; normalize common aliases only in the dataset tooling. The two routines are useful context: when a Push session is active, the classifier can rank five target classes; for Back, six. It must still have an `other / transition` class so it can abstain when the movement is not one of those exercises.

## What the current code already supplies

- [MotionManager.swift](../../StrengthTracker/Shared/Services/Motion/MotionManager.swift) streams Watch device motion at 50 Hz: gravity (3 axes), user acceleration (3 axes), and rotation rate (3 axes).
- [ExercisePeriodDetector.swift](../../StrengthTracker/Shared/Services/Motion/ExercisePeriodDetector.swift) is a hand-written movement-period detector.
- [RepDetector.swift](../../StrengthTracker/Shared/Services/Motion/RepDetector.swift) routes by manually selected exercise. [LateralRaiseRepDetector.swift](../../StrengthTracker/Shared/Services/Motion/LateralRaiseRepDetector.swift) implements the sole rep detector so far, a gravity-angle state machine for left-wrist lateral raises.
- [MotionRecording.swift](../../StrengthTracker/Shared/Services/Motion/MotionRecording.swift) stores opt-in, DEBUG-only labeled JSON on the Watch. It records the selected exercise and reviewed/final set rep total, but not per-rep timing labels. Completed files are automatically queued to the iPhone training-data inbox; model training and dataset curation remain future work.
- The Watch workout path owns live sensor handling and WorkoutSet persists detected reps separately from final user-reviewed reps. The learned classifier should fit behind this existing architecture rather than own workout/session state.

## Research that informs the design

1. **RecoFit / Microsoft Exercise Recognition dataset.** RecoFit separates exercise-period detection, classification, and rep counting. The paper reports 5-second sliding-window features and an SVM classifier, with exercise-period precision/recall above 95%, 96% recognition on a 13-exercise circuit, and rep counts within ±1 for 93% of sets. The associated data provides 50 Hz accelerometer and gyroscope traces from over 200 participants. The 13-class circuit includes useful coarse analogues—row, curl, shoulder press, triceps extension, and back fly—but not OneRep’s exact machine/variation labels. The `singleonly` file is exercise-segmented and useful for exercise identity/counting; `multionly` includes whole-session non-exercise periods and exercise start/end plus rep-total annotations, useful for evaluating segmentation and windowing. Sensor placement is forearm/arm-worn rather than Apple Watch wrist, so treat cross-device results as transfer tests, not target performance. The archived GitHub data repo uses Community Data License Agreement – Permissive 2.0, which allows use, modification, and sharing under its terms; retain the agreement when sharing data and cite the source. ([RecoFit paper](https://www.microsoft.com/en-us/research/publication/recofit-using-wearable-sensor-find-recognize-and-count-repetitive-exercises/), [Microsoft dataset and format guide](https://github.com/microsoft/Exercise-Recognition-from-Wearable-Sensors), [dataset license](https://github.com/microsoft/Exercise-Recognition-from-Wearable-Sensors/blob/main/LICENSE))
2. **Um et al., 50-exercise CNN.** This study trained CNNs on forearm-worn accelerometer/orientation data and reported 92.14% on 50 gym exercises. Its dataset was a large PUSH-company dataset (1,748 athletes in the top-50 subset), not an open dataset OneRep can train against. The study also notes that few-rep/heavy sets were harder to classify than longer sets. This supports trying a CNN, but it underscores the need for many users and realistic low-rep recordings. ([Paper](https://arxiv.org/abs/1610.07031))
3. **Soro et al., smartwatch exercise recognition and rep counting.** A wrist + ankle smartwatch study recorded 54 participants, 10 CrossFit-style exercises, 5,461 reps; it reports 99.96% classification and ±1 count on 91% of sets. It demonstrates the joint task, but CrossFit movements and an additional ankle sensor differ from OneRep's machine/free-weight upper-body set. Treat the high accuracy as study-specific. ([Paper](https://pubmed.ncbi.nlm.nih.gov/30744158/))
4. **INSIGHT-LME rehab exercise study and dataset.** This is the best public starting point found for building the pipeline: it reports a single right-wrist 6-axis IMU sampled at 512 Hz, 76 participants, and classes including biceps curl, front/lateral raise, triceps extension, and pec deck, plus an “Others” class. The paper reports making the dataset public through a short link, though I could not verify that endpoint or a dataset-specific license in this research pass. It reports 97.18% recognition F1 for an AlexNet-based model, but its constrained rehabilitation protocol and sensor differ from OneRep; treat the number as paper-specific. Even if downloadable, this dataset cannot teach the exact OneRep machine variants. ([Paper and dataset link](https://www.mdpi.com/1424-8220/20/17/4791))
5. **Tiny wrist inference for 11 workouts.** Bian et al. use a residual 1D CNN with a 2-second window (40 samples at 20 Hz), normalized 7-channel signal, and 11 activity classes plus Null. They report 90.4% full-precision accuracy under leave-one-subject-out evaluation, with lower accuracy after quantization on microcontrollers. The data includes only 10 people and classes such as arm curl, bench press, leg press, and walking; it also uses body-capacitance sensing and is not a direct model/data match for OneRep. It is evidence that a compact conv model can run locally, not a ready-to-use OneRep model. ([Paper](https://arxiv.org/abs/2301.05748), [UCI RecGym dataset](https://archive.ics.uci.edu/dataset/1128/recgym%3A%2Bgym%2Bworkouts%2Brecognition%2Bdataset%2Bwith%2Bimu%2Band%2Bcapacitive%2Bsensor-7))
6. **MyoGym open exercise set.** The paper describes 30 exercises from 10 people, each with a set of ten repetitions, recorded with a right-forearm Myo armband: 6D motion plus 8-channel EMG. It has useful neighboring movements (for example incline dumbbell press/fly, pulldown, dumbbell rows/curls, and rear-delt raise), but it does not provide Apple Watch-equivalent data or all OneRep machine exercises. It does **not** include preacher curl. The repository record labels the paper itself “not for redistribution”; confirm the actual data access and reuse terms before using it for training. Treat it as taxonomy/method context, not OneRep ground truth. ([Oulu repository and paper record](https://oulurepo.oulu.fi/handle/10024/28308), [paper PDF](https://oulurepo.oulu.fi/bitstream/10024/28308/1/nbnfi-fe202003208605.pdf))
7. **Open rep-counting benchmark.** This GitHub project compares paper-based IMU rep-counting pipelines, including RecoFit-style filtering, PCA, autocorrelation, and peak selection across heterogeneous datasets. It is relevant to improving repetition segmentation/counting, not to recognizing OneRep's eleven exercise identities; some methods are reconstructed interpretations, not original author implementations. ([Repository](https://github.com/gcornella/Movement-Repetition-Counting-for-Wearable-IMUs))
8. **Phan et al., exercise-classification design study.** This open paper/code/data study covers 37 lower-body rehabilitation exercises from 19 adults and systematically tests sensor placement and label granularity. With 10 IMUs it reports 81% accuracy for 37 individual exercises versus about 96% for 10 exercise groups; a single wrist sensor reached 75% for groups, and individual-exercise accuracy was lower. The movements are different from OneRep's, but the key lesson is directly relevant: similar movements are hard to separate, exact labels need more data than broad movement groups, and evaluation must hold out people. ([Paper](https://pmc.ncbi.nlm.nih.gov/articles/PMC11284806/), [open code and data](https://simtk.org/projects/imu-exercise))
9. **Apple Core ML conversion.** Apple’s Core ML Tools supports converting traced/scripted PyTorch models using the unified conversion API. Keep the model input fixed-shape for the first release and compare predictions from the converted model with the Python model on identical saved windows. ([Apple conversion guide](https://apple.github.io/coremltools/docs-guides/source/load-and-convert-model.html))
10. **Resistance-training classification systematic review.** A 2025 review included 44 development/validation studies and 49 models. It found results difficult to compare because exercise sets, devices, and validation methods differ; it recommends standardizing the classification task and reporting model performance rigorously. This means the general field is established, while a well-controlled, reproducible watch-based benchmark could still add value. ([Review](https://link.springer.com/article/10.1007/s40279-025-02281-8))
11. **TransfHAR, on-demand personalized smartwatch recognition (2026 preprint).** This is a close neighbor to the two-workout personalization idea: it learns self-supervised wrist-IMU representations and uses a lightweight classifier trained from a few on-watch examples for user-defined activity classes. Its demonstrations are fine-grained hand/procedural activities rather than resistance-training exercises, so it does not resolve the OneRep task. However, “few-shot personalization on a smartwatch” alone is not a novel claim; a paper should directly compare with or build on this kind of method. ([arXiv preprint](https://arxiv.org/abs/2608.15861))

### Can TransfHAR data be reused for OneRep?

- **For pretraining/representation experiments: potentially, with work.** TransfHAR pools public wrist datasets into a 50 Hz accelerometer/gyroscope stream and reports 381 subjects. Its associated [IMU_LM_Data repository](https://github.com/Abradshaw1/IMU_LM_Data) contains dataset loaders and an alignment pipeline; its README says to download the original raw datasets separately. Thus it is not one downloadable, uniformly licensed dataset. Access and reuse need to be checked source-by-source.
- **For direct 11-exercise supervised training: no.** The released/pooled activity labels are not labels for OneRep’s exact machine exercises. The paper’s personalized activity examples are gestures and daily procedures, not push/pull lifting classes. At most, broad unlabeled wrist motion could support self-supervised encoder pretraining; OneRep still needs labeled Watch examples for each target exercise and for `other / transition`.
- **Signal compatibility is promising but not plug-and-play.** TransfHAR’s 6-axis path uses accelerometer plus gyroscope, standardized to 50 Hz and a forward-left-up axis convention. OneRep samples at 50 Hz but currently stores gravity, user acceleration, and rotation rate as nine channels. To use a TransfHAR-style six-channel encoder, define and verify a transform from OneRep’s motion channels to total acceleration plus gyroscope, including units and watch-axis orientation. Keep the same transform for training and Watch inference.
- **Pretrained weights are a separate question from data availability.** The paper describes a 21.4M-parameter encoder and Core ML watch deployment, but the associated repository I found is a data-unification pipeline; I did not find a published checkpoint or the complete model-training/application code there. Ask the authors or inspect any newer release before planning to use their weights. The simpler route is to reuse their preprocessing/evaluation ideas and train a smaller model on OneRep data.

## Proposed first model

### Task boundary

Train the first model for **exercise identity**, not for the whole workout lifecycle and not for form grading. Keep set boundaries and rep events separate:

1. Existing activity logic or a learned activity gate marks an active set.
2. A classifier ranks the five Push or six Back classes plus `other / transition`.
3. A temporal aggregator combines multiple window predictions into one set-level decision.
4. The existing/manual rep counter remains authoritative for reps until a separately evaluated per-rep model is justified.

If the app asks the user to select an exercise before the set, that selection is already a label and automatic identity is unnecessary. In that mode, use inference only to suggest a correction or discover that the observed movement conflicts with the selection. Keep a one-tap manual override.

### Input and windowing

- Input channels: the same nine values already sampled by OneRep: gravity XYZ, user-acceleration XYZ, rotation-rate XYZ.
- Sample rate: start with the existing 50 Hz Watch stream.
- Candidate first input: fixed tensor `[9 channels, 150 samples]` (3 seconds), advanced every 0.5–1 second. Sweep 2, 3, 4, and 5-second windows during experiments; papers use both short (2-second) and longer (5-second) windows, and individual rep duration varies. Do not pick a window size from literature alone.
- Use timestamps to handle sample gaps and maintain a fixed-rate buffer. Freeze one normalization/orientation transform and share its test vectors between Python and Swift. Avoid per-window normalization that destroys amplitude/range-of-motion information.
- Add `other / transition` examples: rest, walking between machines, changing weight, adjusting equipment, starting/stopping, and movements outside these eleven classes. Exclude or label rep setup/unrack/re-rack clearly.

### Candidate architecture

Start with a compact **1D CNN**:

```text
9 × T motion window
→ Conv1D(32, kernel 7) + normalization + ReLU + pool
→ Conv1D(64, kernel 5) + normalization + ReLU + pool
→ Conv1D(64, kernel 3) + ReLU
→ global average pooling
→ 32-dimensional embedding
→ small dense classifier head
→ 12 logits (11 classes + other)
```

Use categorical cross-entropy with class balancing, dropout/weight decay, and early stopping. Keep the embedding available for the two-workout personalization experiment. This is a baseline architecture to test, not a known best model. Compare it against an SVM or Random Forest trained on simple time-domain statistics, magnitudes, dominant frequency/autocorrelation, and axis-correlations. RecoFit's SVM/window baseline gives OneRep a strong sanity check before adopting a CNN.

### Inference behavior

- Run prediction on a background serial worker, not for every raw sample on the main actor. The current `MotionManager` callback creates a main-actor task per sample, so inference should use a separate window buffer/worker and send only completed predictions back to the Watch workout state.
- Infer at roughly 1–2 times per second rather than 50 times per second. Smooth predictions with a short temporal vote or EMA and accumulate evidence over the set.
- Apply routine context as a prior/mask (Push: 5 classes; Back: 6) while keeping `other` available.
- Return top class, probability, and margin. Only auto-select/log when confidence and class margin pass thresholds calibrated on held-out participants; otherwise show top suggestions and ask. Do not force the highest class on a weak signal.
- Preserve manual selection, existing lateral-raise detector, and manual rep edit as fallbacks. Model output must never silently overwrite final reps or user choice.

## Data collection plan

### Pilot protocol

Use OneRep's actual Series 8 and current MotionManager format. Collect the eleven classes using the target left-wrist position, then add multiple participants and sessions before claiming cross-user performance. A practical engineering pilot is 5–10 lifters over two sessions, with 2–3 sets per exercise per person, ordinary 6–15 rep sets, plus explicit non-exercise/transitions. This is enough to find feasibility and label confusions, not enough to claim broad deployment accuracy.

Capture varied but recorded conditions: weight/intensity, rep speed, grip/stance where relevant, machine model, setup/transition, watch fit/orientation, and dominant wrist. Keep the labels and raw samples tied to session/set IDs. Retain raw data only with a clear development/collection consent and deletion policy.

### Label quality

- Manual selected exercise ID is the set-level class label for OneRep's current flow.
- `detectedReps` and user-final reps provide set totals, not per-rep timestamps. They can supervise the exercise classifier by assigning the set label to active-set windows. They are insufficient by themselves for a neural model that must predict exact rep start/end frames.
- Record or annotate exact set active boundaries; include transitions as `other`, rather than treating every sample from a workout recording as the set's exercise.
- Preserve `detectedReps` and final reps as separate values. A future rep model needs rep event labels or a validated weak-label/alignment process.
- Simulate onboarding honestly during validation: train the global model on other people; give each held-out person only their first two labeled workouts for personalization; evaluate on later workouts from that same person. Also report the global model before personalization. Do not split overlapping windows from a person or set across train/calibration/test.

## Two-workout warmup: practical design

1. **Start with the selected exercise as weak supervision.** While the workout UI has a manually selected exercise, record timestamped 9-channel windows under that exercise ID. Trim warm-up/setup and transitions using set/activity boundaries; ask the lifter to confirm or correct the label after the set.
2. **Build one clean support set per exercise.** In each of the first two workouts, collect only active movement windows for exercises the lifter actually performs. Require several seconds of clean motion and multiple repetitions before creating a personal prototype. A planned-but-skipped exercise gets no calibration sample.
3. **Use a frozen encoder for personalization.** The general model produces an embedding and global class logits. Average the user's clean embeddings per class; at inference, blend prototype similarity with global logits using a conservative weight that rises with sample count and within-class consistency. A small regularized linear head is an alternative to compare. Avoid full CNN fine-tuning on two workouts.
4. **Keep calibration reversible and reviewable.** Store model version, transform version, example count, and per-class confidence locally. Let the user reset personalization. Never silently change the selected exercise or final rep count; show a suggestion and allow correction.
5. **Gate on coverage.** Until enough examples exist for a class, use only the global model and show lower confidence. After two workouts, say which exercises were actually calibrated rather than implying all eleven have been learned.

The first two sessions may be enough to adapt to that person’s watch orientation and movement style, but not to establish that the global model generalizes well. Cross-person accuracy still depends on a much broader labeled dataset.

### Avoiding misleading validation

Split by **person first**, then by workout/session; keep every overlapping window from a set in only one split. Random window splits leak nearly identical sensor traces across train and test. Report leave-one-person-out or grouped person splits, plus per-class metrics. Also report set-level accuracy, macro-F1/balanced accuracy, false auto-selection rate, `other` rejection/coverage, confidence calibration, and latency. Inspect confusion pairs explicitly (pressing variants, pulldown vs row, curl variants, pec/rear-delt fly) rather than hiding them in aggregate accuracy.

Use window shifts, mild sensor noise/gain, small orientation perturbations, and modest time warp only as label-preserving augmentation. Split before augmentation. Confirm the transforms do not erase axis relationships, gravity orientation cues, rep phase, or meaningful amplitude differences.

## Training and deployment workflow

1. In DEBUG builds, the `Collect ML training data` setting records every explicitly started and reviewed set. The selected exercise and corrected rep count are the golden labels; workout, workout-exercise, set, detector, and wrist metadata remain attached to the raw 50 Hz samples.
2. Queue every completed recording with WatchConnectivity file transfer. Retain its Watch copy until delivery succeeds, retry older pending files whenever the session activates, validate the payload on iPhone, and save it under `Documents/MLTrainingData/MotionRecordings` for Files/Finder export. Treat the phone folder as the development dataset inbox, not as a trained-model store.
3. Add a Python data-prep/training folder outside the app target. Import the phone inbox, reject malformed/abandoned samples, freeze the preprocessing manifest, and generate reproducible labeled windows without splitting a set across partitions.
4. Establish participant/workout-grouped train, validation, and untouched test splits before augmentation. Train the simple SVM/RF baseline, then a compact PyTorch 1D CNN against the same partitions.
5. Convert the accepted CNN with Apple `coremltools` to a fixed-shape Core ML package using only supported operations. Keep normalization, channel order, sample rate, window length, label order, dataset revision, and model version in one manifest.
6. Compare Core ML outputs against PyTorch on saved test tensors, then profile latency, memory, and battery on the target Watch. Conversion correctness and good laptop metrics are not a deployment result.
7. Integrate behind an inference protocol, preserving the current rule-based/manual path. Use Core ML compression only after the uncompressed model runs and metrics are known. Ship a known-good global model as an app resource or signed development artifact.
8. Add optional personalization only after the global model is reliable. Keep the CNN encoder frozen and update a small classifier head or per-class embedding prototypes on iPhone from confirmed sets, while idle or charging. Maintain a validation buffer and the previous model, reject regressions, record the base-model/transform versions, and transfer only an accepted personalized artifact to Watch. Never retrain the full CNN automatically after each set.

## Main risk

One wrist mostly observes wrist/forearm motion. A machine can constrain that motion and different exercises can produce similar distal trajectories; some distinctions depend on torso, shoulder, or equipment motion that the watch does not observe. Machine/version, grip, tempo, and user form may shift signals. The model therefore needs realistic target-device data, routine context, an `other` class, and a reliable abstain/manual-confirm behavior. An 11-way softmax always returns an answer, but that does not mean the answer is identifiable from the sensor input.

## Is this a paper-sized research contribution?

The broad topic—IMU-based exercise classification, sliding windows, CNNs, and watch inference—is not new. Nor is few-shot personalization on wrist-worn IMUs by itself. A defensible contribution would be a **specific, reproducible study of personalized recognition for these eleven machine/free-weight push and pull exercises under realistic watch and workout conditions**, ideally with a releasable dataset and a strong person-held-out evaluation.

Possible research questions:

1. How well does a global wrist-IMU model distinguish the eleven exercises for lifters it never saw during training?
2. Does calibration from the first two labeled workouts improve later set-level recognition for those held-out lifters over a global CNN, an SVM/Random Forest baseline, and a simple per-user prototype or linear head?
3. Can an `other`/abstain policy reduce confident wrong selections during transitions and out-of-routine movement while retaining useful coverage?
4. Does the selected model run within Watch latency and battery constraints, and does the Core ML model match the Python model on the same windows?

For a publishable evaluation, split by participant before making overlapping windows. In the personalization experiment, reserve the first two workouts of each held-out participant for calibration and evaluate on later workouts, preferably including a different session and changed machine or tempo where possible. Report per-class and macro metrics, set-level accuracy, false-accept rate and coverage for abstention, calibration quality, inference latency, and the gain from personalization. Size the study from the expected effect and variability; the proposed 5–10-person engineering pilot can reveal collection problems but is not enough to establish broad generalization. Use an approved consent/ethics process for human-subject data collection and publish the exact protocol, label definitions, split rules, and code.

The paper should claim a task-specific benchmark and empirical finding, not a new general CNN architecture. The strongest angle would be whether a small amount of user-specific workout data meaningfully resolves cross-person and equipment variation for this constrained exercise set.

## Bottom line

The evidence supports a **small windowed temporal model for a constrained exercise list**, but strongest results come from task-specific datasets, sensor placement, and careful subject-level validation. Start with a transparent SVM/RF baseline and a 1D CNN on OneRep recordings; use public datasets to learn methods and seed adjacent classes, not as a substitute for Watch Series 8 recordings of these exact eleven exercises.
