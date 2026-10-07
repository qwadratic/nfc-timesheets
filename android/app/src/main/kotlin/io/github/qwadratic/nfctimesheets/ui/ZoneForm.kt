package io.github.qwadratic.nfctimesheets.ui

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import io.github.qwadratic.nfctimesheets.R
import io.github.qwadratic.nfctimesheets.core.WireOperatorLocation

/**
 * WHAT IS THIS CARD, AS A FORM: a zone name, a building, Skip, and submit. One stateless
 * composable because decision-54 §2 and decision-76 §1 ask the operator the identical
 * question at two moments — straight after writing a card (nfc/WriteTagActivity) and when
 * Test a tag finds a card that was written and reported but never named
 * (nfc/VerifyZoneActivity). Two copies of this would drift the day one of them changes.
 *
 * STATELESS ON PURPOSE. Each screen owns its own name, pick and skip flags, and decides what
 * submit does; this only draws them. The name field is REQUIRED and the building is NOT: a
 * zone with no name is a row nobody can pick off a worklist afterwards, while a zone with no
 * building is a documented resting state (decision-54 §1) that a later bind resolves. So
 * "no building" has to be chosen out loud — [skipped] — before submit enables.
 *
 * @param hint optional title above the form; the finish-a-card screen already says it in its
 *   own sentence and passes null.
 */
@Composable
fun ZoneForm(
    hint: String?,
    name: String,
    onNameChange: (String) -> Unit,
    locations: List<WireOperatorLocation>,
    selectedBuildingId: String?,
    onPickBuilding: (WireOperatorLocation) -> Unit,
    skipped: Boolean,
    onSkip: () -> Unit,
    canSubmit: Boolean,
    onSubmit: () -> Unit,
) {
    if (hint != null) Text(hint, style = MaterialTheme.typography.titleMedium)
    OutlinedTextField(
        value = name,
        onValueChange = onNameChange,
        label = { Text(stringResource(R.string.write_zone_name_label)) },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
    // The list itself is ui/BuildingPicker.kt, shared with the bind flow in
    // nfc/VerifyZoneActivity — same question, asked at several moments.
    BuildingPicker(
        locations = locations,
        selectedId = selectedBuildingId,
        emptyText = stringResource(R.string.write_zone_locations_empty),
        onPick = onPickBuilding,
    )
    OutlinedButton(
        onClick = onSkip,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp),
    ) {
        Text(
            if (skipped) {
                "✓ " + stringResource(R.string.write_zone_no_building)
            } else {
                stringResource(R.string.write_zone_no_building)
            },
        )
    }
    Button(
        onClick = onSubmit,
        enabled = canSubmit,
        modifier = Modifier.heightIn(min = 48.dp),
    ) { Text(stringResource(R.string.write_zone_submit)) }
}
