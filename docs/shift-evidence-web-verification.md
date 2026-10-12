# Admin evidence UI verification — 2026-10-10

Executed through the Codex in-app browser against the isolated real API on
`http://127.0.0.1:8087`, PostgreSQL on port 55441. Synthetic company B was used to
avoid changing company A while Android verification was running.

| Action | Observed UI | Persisted/API result |
| --- | --- | --- |
| Sign in and open Easy setup → company | German Shift evidence panel; both settings Off | Existing company default policy loaded |
| Enable location | Interval control appears with 5-minute draft value | No write until Save |
| Enter zero, Save | Browser rejects with minimum-1 validation | No successful save message |
| Enter 2 minutes, require camera, Save | German success message | PUT succeeds |
| Reload page | On / 2 / camera required retained | Fresh GET returns saved company policy |
| Switch interface to English | All new labels, help and buttons translated | Settings retained |
| Disable both and Save | Interval hidden, English saved message | Both settings saved Off |

Desktop visual inspection showed readable labels, inline help, native controls and no
overlap in the evidence form. Policy is separate from the company-name form, so saving
one does not submit the other. No production account or worker data was used.

`pnpm verify` passed: application checks, DE/EN key and ICU parity, spreadsheet checks,
Biome, TypeScript and the production static build. A subsequent `pnpm check` after all
four telemetry scrubbers were synchronized also passed. Impeccable's detector returned
an empty finding list for both new components.

After the Android verifier finished a real emulator-camera capture, the browser signed in
as synthetic company A, opened Anna a's shift at 20:52 Vienna, opened the correction drawer,
and expanded Photo and location evidence. It showed the required-photo status, the 20:59
capture link, and four location rows with five-metre accuracy. Opening the exact rendered
photo link displayed a decoded 720x960 JPEG from the emulator camera. No correction was
saved. This verifies the complete Android camera → API/PostgreSQL → administrator-view path.

Photo/evidence authorization and binary image delivery were also independently exercised
through HTTP by the proof verifier. The browser session used only synthetic test accounts.
