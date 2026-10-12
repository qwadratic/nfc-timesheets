# Periodic location feature verification

Date: 2026-10-10. Isolated worktree: E:/nfc/.worktrees/shift-evidence. No production changes.

## Expected action matrix (enumerated before device execution)

| Surface / role | Action / negative path | Expected server/database result | Expected UI / device result |
|---|---|---|---|
| Web setup / admin | Load company policy | Read existing policy; no mutation | Existing enabled state and interval; loading/error/retry states |
| Web setup / admin | Enable GPS and save 1-minute interval | Policy interval=60 for subsequent shifts | Success state and retained value after reload |
| Web setup / admin | Change interval while worker has open shift | Existing shift snapshot unchanged; next shift uses new policy | Scope explanation says next shift |
| Web setup / admin | Disable GPS and save | Policy interval=0 for subsequent shifts | Interval input hidden; saved state |
| Web setup / admin | Invalid/empty/out-of-range interval; failed read/save | No accidental default overwrite or invalid policy | Validation/error; editable retry path |
| Web shift detail / admin | Expand evidence, refresh, collapse/reopen | Authorized read of shift samples | Timestamp, coordinates, accuracy or empty/error state; refreshed samples |
| API / worker or operator | Attempt admin policy/evidence access | Denied, no mutation or disclosure | Applicable error; no admin screen on phone |
| Android + iOS worker sign-in / idle | Sign in with no active shift; interval off | No GPS sample | No tracking permission prompt or active tracking |
| Android + iOS worker log | Begin enabled shift; grant permission | Active shift snapshot; fresh owned samples at configured minimum interval | Clear tracking disclosure, Android foreground notification / iOS indicator |
| Android + iOS worker log | Deny/cancel permission; approximate permission | Shift stays open; no fabricated GPS; coarse fix accepted if available | Actionable denial state; no crash; work remains usable |
| Android + iOS worker log | Fresh fix before interval; stale fix / invalid accuracy | No excessive or stale samples accepted | No duplicate UI; next eligible fresh fix can send |
| Android + iOS worker background | Home/lock while active | Eligible fresh observations only; OS timing best effort | Visible platform tracking indicator; no claimed exact timing guarantee |
| Android + iOS worker log | Network failure then recovery | Gap rather than replay queue; next fresh fix only | Work remains usable; error where implemented |
| Android + iOS worker log | End shift locally; remote admin ends shift | No further accepted samples | Tracking stops after local end / reconciliation |
| Android + iOS settings | Sign out / session expires / switch worker | No sample attributed to another worker or old shift | Tracking ends, sign-in shown |
| Android + iOS timeout | Reach 8-hour deadline | No samples after active window | Tracking ends; existing timeout resolver remains |
| Android + iOS operator | Open operator tools / scan verification | No worker sample or shift from operator verification | Operator tools work without GPS tracking |
| Android + iOS lifecycle | Relaunch/background OS kill | Never invent missing points or resurrect ended session | Honest gap; re-arm eligible shift only when permitted |

## Execution evidence

Android and browser execution is recorded below. iOS device/simulator execution is unavailable on this Windows host; source inspection cannot satisfy that gate.

### Android runtime observations (Pixel_9, API 36 debug emulator)

- Real app installed from this worktree; only DEBUG endpoint override points to loopback 8087 through adb reverse. Synthetic worker cookie is fixture-only. No production traffic used.
- Company A worker2 active shift `68c3e708-2f3c-4ad7-901a-9e1781549c97`, PostgreSQL fixture `workspace_check_42820` on loopback55441. Its snapshot interval is 60 seconds.
- First launch rendered German disclosure stating 60-second collection and OS-delay caveat.
- Tapping **Später** rendered the actionable disabled-location explanation. Dismissing it left **Schicht läuft** visible; `dumpsys activity services` returned `(nothing)`. Permission refusal did not close the shift.
- After restarting, permission disclosure reappeared. **Standort erlauben** opened Android's native precise/approximate permission sheet. Granting **While using the app** started the actual location foreground service; observed `isForeground=true`, notification418, channel `shift_location`, location service type.
- Injecting a synthetic Vienna fix using the emulator's location input reached real PostgreSQL through the app: first row at `2026-10-10T18:55:21.242Z`, latitude48.208198333333335 longitude16.373798333333333 accuracy5m. Direct database read confirmed the shift still open, snapshot60.
- Additional fixes within that minute did not increase sample count (still1). Home/background left the service foreground and active. Later background observation and stop tests follow below.

Web policy/evidence UI is assigned to the parent agent; its separate evidence must be appended/referenced before declaring overall feature verification complete.
- Background collection confirmed: second persisted row `2026-10-10T18:56:21.340Z` with injected position48.208398333333335/16.373998333333333 while app was at Home. Spacing from first row is60.098seconds, matching configured60-second minimum. This proves emulator execution, not real-device locked-screen/battery behavior or an exact OS timing guarantee.
- Emulator was handed to the proof verifier while the same shift remained active; that verifier owns the real camera-close action and must also observe location service shutdown after closure.

### Remaining verification gates (not claimed passed)

- iOS: no Xcode/simulator/physical device on this Windows host; permission, background updates, location failure UI, termination and session behavior remain unexecuted. Source inspection is not a runtime pass.
- Android: providers disabled, GPS network loss/recovery, remote-close polling, eight-hour expiry, and operator-only sessions were not driven in this pass. Approximate-only service startup was observed, but a coarse GPS row was not independently established. Force-stop/relaunch was exercised; arbitrary OS reclamation and real-device locked-screen behavior remain unverified.
- Web: parent owns the admin UI flow; server integration tests are separate from rendered UI verification.
- Policy is a per-shift snapshot: admin changes apply to the next shift. Existing running shifts intentionally retain their interval.

### Admin browser evidence

Parent's actual browser drive is documented in `docs/shift-evidence-web-verification.md`: companyB policy saved/reloaded in German and English, 0 rejected as enabled interval, and Off verified. CompanyA Anna a shift evidence drawer rendered4 coordinates at5m accuracy and the emulator JPEG. This covers the separate admin policy and sample-review surfaces; it does not replace native device checks.

### Additional Android negative paths (final APK)

- GPS Off: synthetic shift6 (`7ef7effc-8641-427a-b59c-1acda733573e`) snapshot0 rendered **Schicht läuft** with no permission prompt/service. Injected coordinates produced0 database rows. Closed through the fixture API only to prepare the next scenario.
- Native permission denial: enabled shift7 (`a4ad580b-9b7e-44eb-a23f-f4e5ee78d492`) prompted through the real app into Android's native sheet. Tapping **Don't allow** produced the German disabled-location explanation; service inspection returned `(nothing)`.
- Approximate-only grant: using Android test permission provisioning with coarse granted/fine absent, a Home/resume cycle started the foreground service without crashing. This proves service startup only; do not infer a coarse-coordinate persistence pass.
- Runtime permission revocation: with tracking active, revoking fine and coarse grants caused the service to disappear. Restoring them and resuming the app returned foreground tracking while the shift remained open.
- Real sign-out: **Mehr > Abmelden > Abmelden** reached the actual worker sign-in screen. The foreground service changed from active to `(nothing)`. A subsequent synthetic fix left shift7 at one sample, last captured19:04:59.750Z; the server shift stayed open, as expected for account sign-out rather than shift closure.
- Camera-close integration: the proof verifier drove two actual camera closes and observed no location service after each. See `docs/shift-proof-verification.md` for that feature's exact evidence and limitations.

### Verdict and cleanup ownership

Core Android GPS behavior is verified in an emulator against real local HTTP/PostgreSQL: policy Off, enabled interval, native denial, permission recovery/revocation, background update, and logout stop. Remaining matrix rows above are explicitly unverified; iOS runtime is a blocking release-verification limitation. No production deployment or claim of real-device background reliability is made.

This verifier started the otherwise absent Pixel_9 emulator and owns shutting it down after testing. The parent/server agents own the isolated fixture API/PostgreSQL cleanup. No implementation files were changed by this verifier.