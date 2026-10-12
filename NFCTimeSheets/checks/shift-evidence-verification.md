# iOS shift evidence verification

Implementation uses the policy snapshot returned on each shift, so changing company settings affects new shifts only. Location sampling is limited to the signed-in worker's open shift and stops at the eight-hour boundary, explicit close, or sign-out. Core Location callbacks are throttled to the configured interval. iOS may defer callbacks or terminate the app; an exact background interval is not guaranteed. Failed samples are discarded and the next attempt uses a fresh fix.

Proof uses a server challenge obtained before launching the camera. There is no gallery entry point. The JPEG is resized, metadata stripped, and kept only in memory until upload. The returned proof ID and pending close time are stored in the existing SwiftData queue for idempotent recovery. Required-proof closes need an acknowledged upload and close; cancel leaves the local shift open. A shift whose server policy is not yet known needs connectivity before it can be finished. Known proof-disabled shifts retain the existing offline close queue.

## Checks actually run on Windows

- New screen/status text has German and English catalogue entries.
- Info.plist is valid XML with camera/location usage descriptions and location background mode.
- Camera adapter uses `.camera`; no photo library picker APIs occur in it.
- `git diff --check` passes.
- `checks/run.sh`: initial system Bash attempt returned `Bash/E_ACCESSDENIED`; the parent then ran the actual gate using elevated Git Bash, which exited 1: `checks: swift not found. Install Xcode or the Command Line Tools.` Swift/Xcode and an iOS simulator are unavailable. No native compile, simulator walk, physical GPS, or physical camera result is claimed.

## Required native feature matrix (not yet run)

For every row inspect both UI and authenticated server records. Repeat relevant rows in German and English.

| Action | Expected UI | Expected server effect |
| --- | --- | --- |
| Start with location disabled | No permission prompt or tracking status | No samples |
| Start with location enabled; allow permission | Visible tracking explanation, background indicator | Fresh own-shift samples no faster than interval |
| Deny or revoke location permission | Actionable permission status; shift remains usable | No fabricated samples |
| Lock screen / background / stay stationary | OS-dependent updates; no exact interval promise | Only fresh accepted samples |
| Finish, sign out, or reach eight hours | Tracking stops | No subsequent accepted active-shift sample |
| Change policy during a shift | Current shift keeps its snapshot | New shift picks up changed policy |
| Manual stop / same-tag tap / different-tag tap with proof required | Challenge then live camera; no gallery | Close only after proof upload |
| Cancel sheet or camera / deny camera / expired challenge / failed upload | Shift remains open, retry possible | No completed shift |
| Upload succeeds but close response is lost; reopen app | Existing pending close retries | One idempotent close, not a second shift |
| Proof disabled; disconnect and finish | Existing offline queue behavior | Close syncs when connected |
| Never-synced shift; disconnect and finish | Explicit connection requirement | No assumed proof-policy bypass |
| Resolve an automatically closed proof-required shift | New camera photo before resolution | Resolution includes fresh proof ID |
| Worker changes account | No previous-worker location or close upload | Session ownership enforced |

No entitlement or project.pbxproj edits were made. New Swift/resource files are discovered by the existing filesystem-synchronized Xcode group. Info.plist declares the Location updates background mode; confirm that Xcode's target capability view reflects it and perform normal signing/build review on the owner's Mac. Camera and location prompts are localized through de/en InfoPlist.strings.

Apple references:
- https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates
- https://developer.apple.com/documentation/uikit/uiimagepickercontroller/sourcetype-swift.enum
