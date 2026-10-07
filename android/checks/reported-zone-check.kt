// FINISHING A CARD THAT WAS REPORTED BUT NEVER MADE A ZONE (decision-76).
//
//     cd android && ./checks/run.sh          (this runs as part of it)
//
// THE BUG. An operator wrote a card, it was reported (POST /operator/tags) and the zone step
// opened, but POST /operator/tags/:id/resolve-zone was never sent, so the card stayed a
// reported_tags row with no zone and every later tap answered 422 tag_unbound. Test a tag
// classified it as `tag_reported` and offered nothing. decision-76 makes that classification
// the start of a form: resolve-zone, and — when a building was chosen — the unchanged verify
// with the SAME id the phone just read off the card. The scan that found the card IS its test
// scan (decision-47).
//
// WHAT THIS PROVES, by running the SHIPPING core/ReportedZone.kt against a fake that records
// every call in order:
//   * resolve-zone, THEN verify, and verify's place_uuid is the scanned id — never the zone
//     the server answered with, never anything else (decision-76 §2, §6);
//   * Skip (no building) makes NO verify call, and a zone the server reports as unbound is not
//     verified either;
//   * a failed resolve makes no verify call and is classified into the sentence the screen shows;
//   * a failed verify AFTER a successful resolve is "created, not tested yet": exactly two calls,
//     nothing rolled back, nothing retried behind the operator's back;
//   * cancellation is never swallowed.
// ...and, because nfc/VerifyZoneActivity imports android.nfc and cannot run here, the SOURCE
// claims that route the screen through it, and the strings the screen shows exist in both
// languages with the same placeholders.
//
// Only kotlin-stdlib is needed: the fakes answer immediately, so a coroutine started by hand
// completes synchronously and no kotlinx-coroutines jar is involved.

@file:JvmName("ReportedZoneCheck")

package io.github.qwadratic.nfctimesheets.checks

import io.github.qwadratic.nfctimesheets.core.ApiFailure
import io.github.qwadratic.nfctimesheets.core.ReportedZone
import io.github.qwadratic.nfctimesheets.core.WireResolvedZone
import io.github.qwadratic.nfctimesheets.core.WireZoneVerifyResult
import java.io.File
import java.time.Instant
import kotlin.coroutines.Continuation
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.cancellation.CancellationException
import kotlin.coroutines.startCoroutine
import kotlin.system.exitProcess

private var failed = false

private fun expect(ok: Boolean, what: String) {
    if (ok) {
        println("  ok    $what")
    } else {
        System.err.println("FAIL: $what")
        failed = true
    }
}

private fun <T> runSync(block: suspend () -> T): T {
    var out: Result<T>? = null
    block.startCoroutine(Continuation(EmptyCoroutineContext) { out = it })
    return (out ?: error("the coroutine suspended: the fakes must answer immediately")).getOrThrow()
}

private const val SCANNED = "5111d0de-0000-4000-8000-0000000000d3"
private const val BUILDING = "b0000000-0000-4000-8000-000000000001"
private const val NAME = "Tor 3"

/** The zone id is DIFFERENT from the scanned id on purpose: it shows which id goes where. */
private const val ZONE_FROM_SERVER = "20000000-0000-4000-8000-00000000000z"

private fun proof(zoneId: String) = WireZoneVerifyResult(
    id = zoneId,
    name = NAME,
    locationId = BUILDING,
    locationName = "Haus A",
    verifiedAt = Instant.parse("2026-10-07T10:00:00Z"),
    alreadyVerified = false,
)

private class Run(val outcome: ReportedZone.Outcome?, val thrown: Throwable?, val log: List<String>)

private fun drive(
    building: String?,
    resolve: (tag: String, name: String, loc: String?) -> WireResolvedZone,
    verify: (zone: String, place: String) -> WireZoneVerifyResult,
): Run {
    val log = mutableListOf<String>()
    return try {
        val outcome = runSync {
            ReportedZone.finish(
                scannedId = SCANNED,
                name = NAME,
                buildingId = building,
                resolveZone = { tag, name, loc ->
                    log += "resolve-zone tag=$tag name=$name loc=$loc"
                    resolve(tag, name, loc)
                },
                verifyZone = { zone, place ->
                    log += "verify zone=$zone place=$place"
                    verify(zone, place)
                },
            )
        }
        Run(outcome, null, log)
    } catch (e: Throwable) {
        Run(null, e, log)
    }
}

private fun resolvedWith(loc: String?) = { _: String, _: String, _: String? ->
    WireResolvedZone(ZONE_FROM_SERVER, NAME, loc)
}

private val verifyOk = { zone: String, _: String -> proof(zone) }

private fun resolveThrows(t: Throwable) = { _: String, _: String, _: String? -> throw t }
private fun verifyThrows(t: Throwable) = { _: String, _: String -> throw t }

private fun order() {
    println("-- resolve-zone THEN verify, with the id that was read off the card")
    val run = drive(BUILDING, resolvedWith(BUILDING), verifyOk)
    expect(
        run.log == listOf(
            "resolve-zone tag=$SCANNED name=$NAME loc=$BUILDING",
            "verify zone=$ZONE_FROM_SERVER place=$SCANNED",
        ),
        "a building was chosen: exactly [resolve-zone, verify], in that order (log: ${run.log})",
    )
    expect(run.log.size == 2, "...and nothing else was called")
    expect(
        run.log[1].endsWith("place=$SCANNED"),
        "verify's place_uuid is the id that was SCANNED, not the zone id the server answered with",
    )
    expect(
        run.log[1].contains("zone=$ZONE_FROM_SERVER "),
        "verify's URL id is the zone resolve-zone created",
    )
    val outcome = run.outcome
    expect(
        outcome is ReportedZone.Outcome.Verified && outcome.proof.id == ZONE_FROM_SERVER,
        "the outcome is Verified and carries the server's proof",
    )
}

private fun skipMakesNoVerify() {
    println("-- Skip (no building) makes NO verify call")
    val run = drive(null, resolvedWith(null), verifyOk)
    expect(
        run.log == listOf("resolve-zone tag=$SCANNED name=$NAME loc=null"),
        "Skip: exactly [resolve-zone] with no location (log: ${run.log})",
    )
    expect(run.log.none { it.startsWith("verify") }, "Skip: verify was never called")
    expect(run.outcome is ReportedZone.Outcome.CreatedUnbound, "Skip: the outcome is CreatedUnbound")

    // A server that answers a building-less zone must not be verified even if the operator had
    // chosen a building: no card can resolve to a zone with no building (decision-54 section 7).
    val odd = drive(BUILDING, resolvedWith(null), verifyOk)
    expect(odd.log.none { it.startsWith("verify") }, "a zone the server reports UNBOUND is not verified")
    expect(odd.outcome is ReportedZone.Outcome.CreatedUnbound, "...and is CreatedUnbound")
}

private fun resolveFailures() {
    println("-- a failed resolve-zone creates nothing, verifies nothing, and is classified")
    val cases = listOf(
        Triple(ApiFailure(404, "unknown_reported_tag"), ReportedZone.ResolveFailure.UnknownReportedTag, "404 unknown_reported_tag"),
        Triple(ApiFailure(409, "already_resolved"), ReportedZone.ResolveFailure.AlreadyResolved, "409 already_resolved"),
        Triple(ApiFailure(409, "duplicate_zone_name"), ReportedZone.ResolveFailure.DuplicateZoneName, "409 duplicate_zone_name"),
        Triple(ApiFailure(422, "unknown_location"), ReportedZone.ResolveFailure.UnknownLocation, "422 unknown_location"),
        Triple(ApiFailure.network(), ReportedZone.ResolveFailure.Network, "network"),
        Triple(ApiFailure(500, "http_500"), ReportedZone.ResolveFailure.Other, "500"),
        Triple(ApiFailure(422, "invalid_field"), ReportedZone.ResolveFailure.Other, "422 invalid_field"),
    )
    for ((failure, kind, label) in cases) {
        for (building in listOf(BUILDING, null)) {
            val run = drive(building, resolveThrows(failure), verifyOk)
            val outcome = run.outcome
            expect(
                run.log.size == 1 && run.log.none { it.startsWith("verify") },
                "$label (building=${building != null}): exactly one call, no verify",
            )
            expect(
                outcome is ReportedZone.Outcome.NotCreated && outcome.failure == failure,
                "$label (building=${building != null}): NotCreated carrying the failure",
            )
        }
        expect(ReportedZone.classifyResolveFailure(failure) == kind, "$label is classified as $kind")
    }

    val surprise = drive(BUILDING, resolveThrows(IllegalStateException("boom")), verifyOk)
    val surpriseOutcome = surprise.outcome
    expect(
        surpriseOutcome is ReportedZone.Outcome.NotCreated &&
            ReportedZone.classifyResolveFailure(surpriseOutcome.failure) == ReportedZone.ResolveFailure.Other,
        "an exception that is not an ApiFailure becomes NotCreated (code 'unknown'), never a crash",
    )
}

private fun verifyFailsAfterResolve() {
    println("-- verify failing AFTER resolve-zone succeeded: created, not tested, nothing rolled back")
    val failures = listOf(
        ApiFailure(422, "tag_unbound"),
        ApiFailure(422, "zone_mismatch"),
        ApiFailure(404, "unknown_zone"),
        ApiFailure.network(),
        ApiFailure(500, "http_500"),
    )
    for (failure in failures) {
        val run = drive(BUILDING, resolvedWith(BUILDING), verifyThrows(failure))
        val outcome = run.outcome
        expect(
            outcome is ReportedZone.Outcome.CreatedUntested &&
                outcome.zone.id == ZONE_FROM_SERVER && outcome.failure == failure,
            "${failure.code}: CreatedUntested carries the zone and the failure",
        )
        expect(
            run.log.size == 2 && run.log[0].startsWith("resolve-zone") && run.log[1].startsWith("verify"),
            "${failure.code}: exactly [resolve-zone, verify] - no rollback, no second attempt (log: ${run.log})",
        )
    }
    val surprise = drive(BUILDING, resolvedWith(BUILDING), verifyThrows(IllegalStateException("boom")))
    expect(
        surprise.outcome is ReportedZone.Outcome.CreatedUntested,
        "a verify exception that is not an ApiFailure is still CreatedUntested, not 'could not create'",
    )
}

private fun cancellationIsNotSwallowed() {
    println("-- cancellation passes straight through")
    val inResolve = drive(BUILDING, resolveThrows(CancellationException("cancelled")), verifyOk)
    expect(inResolve.thrown is CancellationException && inResolve.outcome == null, "cancelled during resolve-zone: rethrown")
    val inVerify = drive(BUILDING, resolvedWith(BUILDING), verifyThrows(CancellationException("cancelled")))
    expect(inVerify.thrown is CancellationException && inVerify.outcome == null, "cancelled during verify: rethrown")
}

// ---- what the screen does with it, read from the source (it imports android.nfc) --------------

private val VERIFY_SCREEN = File("app/src/main/kotlin/io/github/qwadratic/nfctimesheets/nfc/VerifyZoneActivity.kt")

private fun sourceClaims() {
    println("-- VerifyZoneActivity routes finishing a reported card through ReportedZone.finish")
    val src = VERIFY_SCREEN.readText()

    expect(
        Regex("""is ScanStep\.TagReported -> stringResource\(R\.string\.verify_scan_any_reported\)""").containsMatchIn(src),
        "the tag_reported status still renders its sentence",
    )
    expect(
        src.contains("(scanStep as? ScanStep.TagReported)?.let { ReportedZoneSection(it.id) }"),
        "the tag_reported classification now draws the zone step, with the id that was read off the card",
    )
    expect(
        src.contains("beginReported(placeUuid, sameCard = previousReported == placeUuid)") &&
            src.contains("scanStep = ScanStep.TagReported(placeUuid)"),
        "the id handed to the form is the scanned place id (the same one classifyTag was asked about)",
    )

    val submit = src.substringAfter("private fun submitReported(").substringBefore("private fun applyReportedOutcome(")
    expect(submit.isNotBlank() && submit != src, "the extraction of submitReported() worked")
    expect(submit.contains("ReportedZone.finish("), "submitReported() calls ReportedZone.finish")
    expect(submit.contains("scannedId = tagId,"), "...with the card's id as the scanned id")
    expect(
        submit.split("operatorApi.resolveZone(").size - 1 == 1 && submit.split("operatorApi.verifyZone(").size - 1 == 1,
        "...and makes exactly one resolve-zone call and one verify call, both as arguments to finish",
    )
    expect(
        submit.indexOf("ReportedZone.finish(") < submit.indexOf("operatorApi.resolveZone(") &&
            submit.indexOf("ReportedZone.finish(") < submit.indexOf("operatorApi.verifyZone("),
        "...neither of them outside it",
    )
    expect(submit.contains("(reportedSkipped) null else reportedBuilding"), "Skip hands finish NO building")

    // decision-76 section 6: the only verify call sites in the screen are the test scan's and finish's.
    val verifyCalls = src.split("operatorApi.verifyZone(").size - 1
    expect(verifyCalls == 2, "operatorApi.verifyZone( is called in exactly two places (test scan, finish): $verifyCalls")
    val resolveCalls = src.split("operatorApi.resolveZone(").size - 1
    expect(resolveCalls == 2, "operatorApi.resolveZone( is called in exactly two places (write-fresh recovery, finish): $resolveCalls")
}

// ---- strings: German default, English, same keys, same placeholders ----------------------------

private fun stringsOf(path: String): Map<String, String> =
    Regex("""<string name="([^"]+)">(.*?)</string>""", RegexOption.DOT_MATCHES_ALL)
        .findAll(File(path).readText())
        .associate { it.groupValues[1] to it.groupValues[2] }

private fun placeholders(text: String): List<String> =
    Regex("""%\d+\$[sd]""").findAll(text).map { it.value }.sorted().toList()

private fun strings() {
    println("-- the strings: both languages, same placeholders, every one used")
    val de = stringsOf("app/src/main/res/values/strings.xml")
    val en = stringsOf("app/src/main/res/values-en/strings.xml")
    val keys = de.keys.filter { it.startsWith("verify_reported_") } + "verify_scan_any_reported"
    expect(keys.size >= 12, "the finish-a-card strings exist (${keys.size} keys)")
    for (key in keys) {
        val d = de[key]
        val e = en[key]
        expect(!d.isNullOrBlank() && !e.isNullOrBlank(), "$key is non-empty in German and English")
        if (d != null && e != null) {
            expect(placeholders(d) == placeholders(e), "$key has the same placeholders in both languages")
        }
    }
    val src = VERIFY_SCREEN.readText()
    val used = Regex("""R\.string\.(verify_reported_[a-z_]+)""").findAll(src).map { it.groupValues[1] }.toSet()
    expect(used.isNotEmpty() && used.all { it in de && it in en }, "every verify_reported_* string the screen uses exists in both files")
    expect(
        de.keys.filter { it.startsWith("verify_reported_") }.all { it in used },
        "...and no verify_reported_* string is left unused",
    )
    expect(
        de.getValue("verify_scan_any_reported").contains("Zone benennen"),
        "the German tag_reported sentence is an invitation to finish the card, not 'nobody has made it a zone'",
    )
    val failureText = src.substringAfter("private fun reportedFailureText(").substringBefore("/** Back to nothing")
    expect(
        failureText.split(", code)").size - 1 == 1,
        "only the catch-all failure shows a raw code; every named refusal is a sentence",
    )
}

fun main() {
    order()
    skipMakesNoVerify()
    resolveFailures()
    verifyFailsAfterResolve()
    cancellationIsNotSwallowed()
    sourceClaims()
    strings()
    if (failed) {
        System.err.println("reported-zone-check: FAILED")
        exitProcess(1)
    }
    println("reported-zone-check: OK")
}
