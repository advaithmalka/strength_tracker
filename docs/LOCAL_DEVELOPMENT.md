# OneRep local development

## Source and tools

The working clone is `/Volumes/OneRepDev/OneRep`, an APFS disk image stored in `OneRepDev.sparsebundle` on the Samsung USB drive. The `origin` remote is the user's GitHub fork; `upstream` points to the MIT-licensed base project. Keep development work in this APFS clone so Git, Xcode, symlinks, and file permissions work normally. The earlier direct ExFAT clone on the Samsung volume is not the working copy.

This project needs Xcode with iOS and watchOS SDKs, Xcode command line tools, Git, and XcodeGen. Its Swift package is local and has no remote package dependencies. This Mac has Git, Apple command line tools, and XcodeGen installed. Xcode 26.6 is unpacked at `/Volumes/OneRepDev/Xcode.app`; use its developer directory explicitly so the system command line tools can remain selected. Its first launch requires the Mac administrator to review and accept Apple's Xcode and SDK license in Terminal:

```sh
sudo DEVELOPER_DIR='/Volumes/OneRepDev/Xcode.app/Contents/Developer' xcodebuild -license
```

If the APFS image is not mounted, attach it with:

```sh
hdiutil attach '/Volumes/Samsung USB/OneRepDev.sparsebundle'
```

Keep the Samsung drive attached while using Xcode or Simulator. On this Mac,
`~/Library/Developer/CoreSimulator/Devices` links to
`/Volumes/OneRepDev/SimulatorDevices`, and
`~/Library/Developer/Xcode/DerivedData` links to
`/Volumes/OneRepDev/DerivedData`. `~/Applications/Xcode.app` links to the
external Xcode app. The Watch simulator booted successfully with
its app container resolving through the external device link. Xcode itself and
the OneRep clone are also on the external APFS volume. If either link appears
broken, mount the sparsebundle before opening Xcode; do not let Xcode create a
new empty directory in its place.

Installed simulator runtime images are managed by macOS. The active watchOS
runtime remains in `/System/Library/AssetsV2`, and the iOS runtime is not
currently installed. A byte-identical 7.9 GB iOS image remains in
`/Library/Developer/CoreSimulator/Cryptex/Images/Inbox`; macOS denied its
removal even with administrator privileges. Its verified backup is the iOS
exported bundle on the Samsung drive. Do not disable System Integrity Protection
or replace managed runtime directories with symlinks to move these images.

## Generate and build

```sh
export DEVELOPER_DIR='/Volumes/OneRepDev/Xcode.app/Contents/Developer'
export TMPDIR='/Volumes/OneRepDev/tmp/'
cd '/Volumes/OneRepDev/OneRep/StrengthTracker'
xcodegen generate
xcodebuild -project StrengthTracker.xcodeproj -scheme StrengthTracker \
  -destination 'generic/platform=iOS' \
  -derivedDataPath '/Volumes/OneRepDev/DerivedData' \
  -jobs 2 \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project StrengthTracker.xcodeproj -scheme StrengthTrackerWatch \
  -destination 'generic/platform=watchOS' \
  -derivedDataPath '/Volumes/OneRepDev/DerivedData' \
  -jobs 2 \
  CODE_SIGNING_ALLOWED=NO build
```

The iOS target embeds the Watch app. Xcode 26.6 requires iOS and watchOS platform support to offer generic build destinations, even with signing disabled. Install those simulator runtimes through Xcode Settings → Components or Apple's `xcodebuild -downloadPlatform` / `-importPlatform` commands before building. Running on the user's devices also requires Xcode signing and a paired Watch.

On this Mac, Xcode 26.6 and watchOS 26.5 Simulator are installed. The iOS 26.5 Simulator runtime was removed after validation because internal storage was too low to keep both simulators available. Its complete exported backup is at `/Volumes/OneRepDev/Platforms/iphonesimulator_26.5_23F77.exportedBundle`. Both generic device builds and the iPhone simulator build completed on September 25, 2026 with signing disabled; the iPhone and Watch apps each launched separately in Simulator. The Watch manual set review and rest timer were checked in Simulator. Motion detection and live paired-device sync still need physical-device or paired-simulator validation.

Restore the iOS runtime only after the Mac has roughly 25–30 GB free internally for installation staging, simulator data, and swap:

```sh
DEVELOPER_DIR='/Volumes/OneRepDev/Xcode.app/Contents/Developer' \
  xcodebuild -importPlatform '/Volumes/OneRepDev/Platforms/iphonesimulator_26.5_23F77.exportedBundle'
```

A build can temporarily use several gigabytes of internal swap even though derived data and temporary build files are directed to the external volume. On September 25, an incremental Watch build was interrupted when free internal space fell below 1 GB; do not retry builds at that margin. Recoverable caches moved to `/Volumes/OneRepDev/StorageRelief` remain available there if they need to be restored.

## Working conventions

- OneRep V1 behavior and the exercise list are in [ONE_REP_MVP.md](ONE_REP_MVP.md).
- The Watch owns active sessions. It saves each confirmed set locally and transfers completed workouts through WatchConnectivity.
- Motion recording is an opt-in developer setting. Recordings stay in the Watch app's `Documents/MotionRecordings` directory.
- Keep new work in focused Git commits so features can be inspected or rolled back individually.
