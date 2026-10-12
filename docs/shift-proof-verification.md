# Photo proof-of-work feature verification

Date: 2026-10-10. Local isolated worktree; synthetic fixture only, no production data.

## Action matrix (before runtime execution)

| Screen / role | Action or negative path | Expected database/API outcome | Expected rendered outcome |
|---|---|---|---|
| Company setup / admin | Enable, disable, save, reload photo policy | Company policy persists; only future shifts use edits | Checkbox retains state and explains scope |
| Company setup / admin | Failed read/save | No accidental overwrite | Error and retry remain usable |
| Worker shift / Android and iOS | Manual stop with proof enabled | Challenge then new JPEG then close linked to proof | Native camera; no gallery selector; completed shift only after success |
| Worker shift / Android and iOS | NFC stop, building switch | Same proof gate; switch starts successor only after close | Capture required; cancellation leaves original running |
| Worker camera / Android and iOS | Cancel/back, deny permission, unavailable camera | No close and no photo accepted | Actionable error; running shift still visible; retry works |
| Worker camera / Android and iOS | Retake, accept | Only accepted fresh photo uploaded | Native retake/accept controls, no gallery import |
| Worker camera / Android and iOS | Offline, failed upload, expired challenge/photo | No unfinished close; no stale evidence accepted | Honest error; new attempt/retry reachable |
| Worker camera / Android and iOS | Process death, sign-out/session change | No other worker attribution; server shift unchanged | Fresh attempt required; no silent completion |
| Worker timeout resolver / Android and iOS | Resolve 8-hour shift | Server auto-close allowed; human resolution requires fresh proof | Camera required before successful resolution |
| Worker shift / Android and iOS | Proof disabled | Existing close path, no challenge | No camera requested |
| Shift drawer / admin | Open evidence/photo, refresh | Authorized tenant read; private JPEG no-store | Captured time and photo or clear empty/error state |
| Server / worker/operator/other company | Access another shift/proof or admin policy | 401/404, no mutation or disclosure | No unauthorized evidence |
| Server / worker | Forged ID, malformed/oversize JPEG, stale proof, repeated close | Reject invalid evidence; completed close idempotent | Error mapped without duplicate shifts |

## Results

Android emulator and live HTTP results are recorded below. iOS runtime blocked on Windows (no Xcode/simulator/device); static inspection is not runtime verification.

### Independent live HTTP checks

- Active shift `68c3e708-2f3c-4ad7-901a-9e1781549c97`: ordinary, manual and auto_closed close requests without a photo each returned 422 `proof_required`.
- Worker cookie on admin evidence returned 401 `unauthorized`.
- Admin A read of closed synthetic fixture `421a82e1-eb7c-4e9d-b227-f13645db8bfd` returned 200 with linked proof `77286662-4719-4747-af3b-5ea5bac1b439`.
- Photo returned 200 `image/jpeg`, `Cache-Control: no-store`, 646 bytes (synthetic blue JPEG).
- These are independent live requests, not claims inferred from source or from another agent's test output.

### Android emulator driven UI (synthetic scene)

- Existing worker session + enabled proof shift opened through real manual-stop controls (`Ohne Tag beenden` → `Jetzt beenden`), not a simulated successful response.
- Native camera exposed shutter/options, then Retake/Done/Cancel. No gallery/import control or picker appeared in this flow.
- Back/cancel returned to the stop dialog with German error explaining a fresh camera photo is required and the shift remains open. Retry reopened camera; Retake returned to live capture. These checks preceded installation of final incremental APK; same camera implementation.
- Final incremental debug APK installed successfully before completion tests. Successful virtual-scene capture returned `Schicht beendet`, `Gesendet`. PostgreSQL shift4 (`68c3e708-2f3c-4ad7-901a-9e1781549c97`) closed at `2026-10-10T18:59:57.815Z`, proof `9e5bb64c-ffb0-4f64-846e-b2134a1abbb9`. Admin evidence independently returned that capture. Location service listing was empty after close.
- Local HTTP proxy8088 forwarded requests to fixture8087, deliberately destroyed the first successful `/shifts/close` response after upstream commit. Proxy logged `DROPPED COMMITTED CLOSE`; app reached completed/sent state without another camera. PostgreSQL shift5 (`f4b57fdb-838d-485a-9a0d-2d38d4488f0a`) closed at `2026-10-10T19:02:24.949Z`, proof `09da0f69-fa1d-416f-8fa0-0cd4c85546c1`. Service again absent.
- This fault injection proves transport-level lost-response recovery (automatic network retry); it does NOT independently execute the persisted-proof manual retry branch.
- DEBUG override restored to8087,8088 reverse removed, emulator handed to GPS verifier signed in with no open shift. No physical camera/user photo used.

### Remaining runtime gaps

- iOS build/device/simulator is unavailable on this Windows machine. Camera permissions, physical capture, cancellation, switching and timeout-resolution UI must be driven on a Mac/device before claiming full cross-platform verification.
- Android camera permission denial/unavailable-camera, expiration while camera remains open, offline upload, process death during capture, proof-enabled NFC stop/building switch, timeout resolver and the persisted-proof manual retry branch were not individually driven in this pass. Existing server contract checks cover API freshness/ownership/resolve semantics but cannot substitute for these UI paths.
- Parent separately verified admin policy and viewed the emulator photo in the evidence drawer. That evidence belongs to the parent's web report, not independent execution here.
