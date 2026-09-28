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

`~/Library/Developer/Xcode/iOS DeviceSupport` links to
`/Volumes/OneRepDev/iOSDeviceSupport`. Xcode can copy several gigabytes of
symbols from a connected iPhone into that directory. Keep the external volume
mounted before connecting a device in Xcode.

Installed simulator runtime images are managed by macOS. The active watchOS
runtime remains in `/System/Library/AssetsV2`, and the iOS runtime is not
currently installed. A failed install can leave a 7.9 GB iOS image in
`/Library/Developer/CoreSimulator/Cryptex/Images/Inbox`. Terminal with Full
Disk Access is needed to remove a protected duplicate after checking it against
the verified iOS exported bundle on the Samsung drive. Do not
disable System Integrity Protection or replace managed runtime directories with
symlinks to move these images.

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

For a physical install, open `StrengthTracker.xcodeproj` in Xcode, sign in under
Xcode Settings → Apple Accounts, and choose the Personal Team under Signing &
Capabilities for the iPhone app, Watch app, and both widget targets. XcodeGen
does not save this local team choice; choose it again after regenerating the
project. The Personal Team cannot provision Time Sensitive Notifications, so
OneRep uses standard rest alerts. The connected iPhone needs Developer Mode;
the paired Watch must also be discovered and enabled for development. Xcode
currently marks the physical iPhone destination ineligible until iOS 26.5
platform support is installed.

Restore the iOS runtime only after the Mac has at least 30–35 GB free internally for installation staging, simulator data, and swap. Attempts with about 22 GB free failed with CoreSimulator disk-space error 14. Both `xcodebuild -importPlatform` and direct `simctl runtime add` copied about 8 GB internally and ignored an external `TMPDIR` for that staging step:

```sh
DEVELOPER_DIR='/Volumes/OneRepDev/Xcode.app/Contents/Developer' \
  xcodebuild -importPlatform '/Volumes/OneRepDev/Platforms/iphonesimulator_26.5_23F77.exportedBundle'
```

A build can temporarily use several gigabytes of internal swap even though derived data and temporary build files are directed to the external volume. On September 25, an incremental Watch build was interrupted when free internal space fell below 1 GB; do not retry builds at that margin. Recoverable caches moved to `/Volumes/OneRepDev/StorageRelief` remain available there if they need to be restored.

## Working conventions

- OneRep V1 behavior and the exercise list are in [ONE_REP_MVP.md](ONE_REP_MVP.md).
- The Watch owns active sessions. It saves each confirmed set locally and transfers completed workouts through WatchConnectivity.
- Motion recording is an opt-in developer setting. Each reviewed recording is queued for durable WatchConnectivity file transfer. The Watch retains the source until delivery succeeds; the iPhone validates and stores it in `Documents/MLTrainingData/MotionRecordings`, visible in Files under `On My iPhone/OneRep/MLTrainingData`.
- Keep new work in focused Git commits so features can be inspected or rolled back individually.
