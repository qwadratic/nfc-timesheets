import { apiFetch } from '@/lib/api'

export type ShiftPolicy = {
  location_interval_seconds: number
  proof_of_work_required: boolean
}

export const fetchShiftPolicy = (signal?: AbortSignal) =>
  apiFetch<{ policy: ShiftPolicy }>('/admin/shift-policy', { signal })

export const saveShiftPolicy = (policy: ShiftPolicy) =>
  apiFetch<{ policy: ShiftPolicy }>('/admin/shift-policy', { method: 'PUT', body: policy })

export type ShiftEvidence = {
  shift: ShiftPolicy & { id: number; client_uuid: string; proof_id: string | null }
  samples: {
    sample_uuid: string
    captured_at: string
    latitude: number
    longitude: number
    accuracy_m: number
  }[]
  proof: { id: string; captured_at: string; received_at: string } | null
}

export const fetchShiftEvidence = (uuid: string, signal?: AbortSignal) =>
  apiFetch<ShiftEvidence>(`/admin/shifts/${encodeURIComponent(uuid)}/evidence`, { signal })

/**
 * Same base lib/api.ts prefixes every request with. Normally empty (same origin); a split
 * dev setup sets it, and then an `<img src>` without it would ask the web server, not the API.
 */
const API_BASE_URL = (process.env.NEXT_PUBLIC_API_BASE_URL ?? '').replace(/\/+$/, '')

export const shiftProofUrl = (uuid: string, proofId: string) =>
  `${API_BASE_URL}/admin/shifts/${encodeURIComponent(uuid)}/proof/${encodeURIComponent(proofId)}`

export type ShiftSample = ShiftEvidence['samples'][number]

/** `?evidence=<client_uuid>` on /shifts/ opens the evidence view. The deep-link contract. */
export const EVIDENCE_PARAM = 'evidence'

/** The shift log's deep link to one shift's photo and GPS trail. */
export const shiftEvidenceHref = (uuid: string) =>
  `/shifts/?${EVIDENCE_PARAM}=${encodeURIComponent(uuid)}`
