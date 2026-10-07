package io.github.qwadratic.nfctimesheets.core

import kotlin.coroutines.cancellation.CancellationException

/**
 * FINISHING A CARD THAT WAS WRITTEN AND REPORTED BUT NEVER MADE A ZONE (decision-76).
 *
 * Test a tag finds such a card (`GET /operator/tags/:id` answers `tag_reported`) and the
 * operator turns it into a zone right there. This file is the ORDER of the two calls that
 * follow, and nothing else, so android/checks/reported-zone-check.kt can pin it on a plain
 * JVM without a phone, a card or a server:
 *
 *   1. resolve-zone  the card becomes a zone (a name, and a building unless Skip was chosen).
 *   2. verify        ONLY when the zone came back with a building, and with the id the phone
 *                    READ OFF THE CARD as `place_uuid`. That is the whole point of the
 *                    decision: the scan that found the card IS its test scan (decision-47),
 *                    so the operator is not asked to prove the same bytes twice.
 *
 * SKIP MAKES NO VERIFY CALL. A zone without a building cannot be resolved by `activePlace`
 * at all, so there is nothing for a scan to prove yet (decision-54 §7); the screen falls
 * into the bind picker that already exists.
 *
 * NOTHING HERE LETS A ZONE BECOME VERIFIED WITHOUT A SCAN OF ITS OWN CARD (decision-76 §6).
 * The `placeUuid` handed to [finish]'s verify is the id read off the card and nothing else,
 * and the server's own equality check (the scanned id must BE the zone) still applies.
 *
 * A RESOLVE FAILURE IS A VALUE, NOT AN EXCEPTION: nothing was created, the screen says why
 * and the operator can try again. A VERIFY FAILURE IS NOT "COULD NOT CREATE" — by then the
 * zone exists, and reporting it as not created would be false. It comes back as
 * [Outcome.CreatedUntested] and the screen offers the ordinary test scan. NOTHING IS ROLLED
 * BACK and nothing is lost: this object has no way to undo a call, because it is handed none.
 *
 * Makes NO network calls of its own, NO SQLite calls and NO Android calls: the two calls are
 * passed in, which is what lets a check observe them in order.
 */
object ReportedZone {

    sealed interface Outcome {
        /** Created with a building and proved by the scan that found the card. */
        data class Verified(val zone: WireResolvedZone, val proof: WireZoneVerifyResult) : Outcome

        /** Created WITHOUT a building. Not verified, on purpose; no verify call was made. */
        data class CreatedUnbound(val zone: WireResolvedZone) : Outcome

        /**
         * Created with a building, but the verify call failed. The zone exists and is not
         * tested yet; [failure] is what the verify call said.
         */
        data class CreatedUntested(val zone: WireResolvedZone, val failure: ApiFailure) : Outcome

        /** resolve-zone did not land: nothing was created and no verify call was made. */
        data class NotCreated(val failure: ApiFailure) : Outcome
    }

    /**
     * Every refusal `POST /operator/tags/:id/resolve-zone` can produce that has its own next
     * move for the operator. The screen turns each into a sentence — never a bare code.
     */
    enum class ResolveFailure {
        /** 404 unknown_reported_tag: the report is not (or no longer) on the server. */
        UnknownReportedTag,

        /** 409 already_resolved: somebody already made this card into something. */
        AlreadyResolved,

        /** 409 duplicate_zone_name: a live zone of that building already has that name. */
        DuplicateZoneName,

        /** 422 unknown_location: the picked building does not exist (any more). */
        UnknownLocation,

        /** No answer at all: offline, DNS, timeout, TLS. Retryable as it stands. */
        Network,

        /** Anything else. The screen shows the raw code inside a translated sentence. */
        Other,
    }

    fun classifyResolveFailure(failure: ApiFailure): ResolveFailure = when {
        failure.code == "network" -> ResolveFailure.Network
        failure.code == "unknown_reported_tag" -> ResolveFailure.UnknownReportedTag
        failure.code == "already_resolved" -> ResolveFailure.AlreadyResolved
        failure.code == "duplicate_zone_name" -> ResolveFailure.DuplicateZoneName
        failure.code == "unknown_location" -> ResolveFailure.UnknownLocation
        else -> ResolveFailure.Other
    }

    /**
     * @param scannedId the id that was just read off the card. It is both the tag the zone is
     *   made from AND the `place_uuid` the verify call carries — never anything else.
     * @param buildingId the building the operator picked, or null when they chose Skip.
     * @param resolveZone POST /operator/tags/:id/resolve-zone (tagId, name, locationId?).
     * @param verifyZone POST /operator/zones/:id/verify (zoneId, placeUuid).
     */
    suspend fun finish(
        scannedId: String,
        name: String,
        buildingId: String?,
        resolveZone: suspend (tagId: String, name: String, locationId: String?) -> WireResolvedZone,
        verifyZone: suspend (zoneId: String, placeUuid: String) -> WireZoneVerifyResult,
    ): Outcome {
        val zone = try {
            resolveZone(scannedId, name, buildingId)
        } catch (e: CancellationException) {
            throw e
        } catch (e: ApiFailure) {
            return Outcome.NotCreated(e)
        } catch (_: Exception) {
            return Outcome.NotCreated(ApiFailure(status = 0, code = "unknown"))
        }

        // Verified only when the operator CHOSE a building AND the server says the zone has
        // one. Either alone is not enough: Skip must never verify, and a zone the server
        // reports as unbound cannot be proved by any card.
        if (buildingId == null || zone.locationId == null) return Outcome.CreatedUnbound(zone)

        return try {
            Outcome.Verified(zone, verifyZone(zone.id, scannedId))
        } catch (e: CancellationException) {
            throw e
        } catch (e: ApiFailure) {
            Outcome.CreatedUntested(zone, e)
        } catch (_: Exception) {
            Outcome.CreatedUntested(zone, ApiFailure(status = 0, code = "unknown"))
        }
    }
}
