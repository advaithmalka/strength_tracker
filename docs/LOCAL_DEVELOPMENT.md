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

## Generate and build

```sh
export DEVELOPER_DIR='/Volumes/OneRepDev/Xcode.app/Contents/Developer'
cd '/Volumes/OneRepDev/OneRep/StrengthTracker'
xcodegen generate
xcodebuild -project StrengthTracker.xcodeproj -scheme StrengthTracker \
  -destination 'generic/platform=iOS' \
  -derivedDataPath '/Volumes/OneRepDev/DerivedData' \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project StrengthTracker.xcodeproj -scheme StrengthTrackerWatch \
  -destination 'generic/platform=watchOS' \
  -derivedDataPath '/Volumes/OneRepDev/DerivedData' \
  CODE_SIGNING_ALLOWED=NO build
```

The iOS target embeds the Watch app. Xcode 26.6 requires iOS and watchOS platform support to offer generic build destinations, even with signing disabled. Install those simulator runtimes through Xcode Settings → Components or Apple's `xcodebuild -downloadPlatform` / `-importPlatform` commands before building. Running on the user's devices also requires Xcode signing and a paired Watch.

## Working conventions

- OneRep V1 behavior and the exercise list are in [ONE_REP_MVP.md](ONE_REP_MVP.md).
- The Watch owns active sessions. It saves each confirmed set locally and transfers completed workouts through WatchConnectivity.
- Motion recording is an opt-in developer setting. Recordings stay in the Watch app's `Documents/MotionRecordings` directory.
- Keep new work in focused Git commits so features can be inspected or rolled back individually.
