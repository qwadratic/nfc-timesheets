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

export const shiftProofUrl = (uuid: string, proofId: string) =>
  `/admin/shifts/${encodeURIComponent(uuid)}/proof/${encodeURIComponent(proofId)}`
