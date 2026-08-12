---
id: decision-34
title: m2 per hour is a planning figure about places and never a rating of people
date: '2026-08-12 05:47'
status: proposed
---
## Context

Zone areas (decision-33, `area_dm2`) exist so the business can compute a productivity figure:

```
Flächenleistung = area_dm2 / 100 / (payable_minutes / 60)      m² per hour
```

The figure is genuinely useful for pricing: quoting a 400 m² stairwell is guesswork today and
becomes arithmetic once there is a historical rate for stairwells.

It is also one `GROUP BY worker_id` away from being a staff league table, and somebody will
write that query. A cleaner assigned the worst rooms will look slow, and the number carries
none of the context that would explain it. On a system that already computes people's pay,
that is not a reporting nicety — it is the difference between a planning tool and an
accusation.

A warning in a document is not a control. This record states the controls.

## Decision

**m²/h is computed and displayed per ZONE. There is no per-worker productivity screen and no
export that produces one by accident.**

Seven mechanisms, each attached to a specific way the number lies:

1. **Assignment bias** — a worker figure may appear ONLY inside a single zone, compared
   against that zone's own median. Never across zones, never as a ranking.
2. **Area is not effort** — 40 m² of open office is not 40 m² of stairwell with 60 steps and
   a handrail. The default comparison is therefore a zone against **its own history**, not
   against other zones.
3. **Small samples** — every rate renders with its shift count. Below **n = 5** the panel
   shows `n = 3 — zu wenig Daten` and **no number at all**. Suppression, not a caveat printed
   next to a number people will quote anyway.
4. **Unconfirmed end times** — shifts with `auto_closed AND corrected_at IS NULL`
   (decision-10) are excluded. They are already excluded from payroll and the two must not
   disagree about what a real hour is.
5. **Missed zone taps** — a worker who forgets to tap zone B inflates zone A and erases
   zone B. A segment longer than **3× the zone's median** is excluded and counted as
   `unplausibel`, and **that count is shown**. An invisible exclusion is a lie.
6. **Rollup paradox** — the building figure is shown BESIDE the zone rows, never instead of
   them, so a zone that got worse cannot hide inside a stable total.
7. **Unmeasured zones** — `area_dm2` is NULLable; a zone without an area is simply absent from
   productivity and is never treated as 0 m².

The thresholds in 3 and 5 are stated in one place in code, named, and cited back to this
record.

## Consequences

**The most important rule is the product one, not the statistics.** No per-worker productivity
screen exists. If the owner later asks for one, that is a new decision record, and this list
is the argument it has to answer.

**n = 5 and 3× are invented numbers.** They are the right shape — suppress small samples,
exclude implausible segments — but there are 8 shifts in production, so nothing calibrated
them. They must be revisited once there is enough data to plot, and the code must make them
easy to change without hunting.

**Suppression will be unpopular before it is trusted.** A director who adds one zone and does
four cleans sees "zu wenig Daten" and may read it as the feature being broken. The empty state
must say what is missing and how many more (`noch 2 Schichten`), not merely refuse.

**The report is a planning input, so it belongs next to contracts, not next to payroll.**
Placing it on the payroll screen would make the wrong reading the obvious one.

Supersedes nothing. Depends on decision-33 (`area_dm2`, zone rows) and decision-10 (the
auto-close flags that define an unconfirmed hour). Consistent with decision-30, which already
requires payroll and reports to resolve from the same source rather than two.
