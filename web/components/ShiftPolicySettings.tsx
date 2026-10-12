'use client'

import { useTranslations } from 'next-intl'
import { type FormEvent, useCallback, useEffect, useId, useState } from 'react'
import { Field } from '@/components/Field'
import { ListPanel } from '@/components/ListPanel'
import { ApiError } from '@/lib/api'
import { fetchShiftPolicy, type ShiftPolicy, saveShiftPolicy } from '@/lib/shiftEvidence'

/** Company policy is loaded before editing; defaults must never overwrite a failed read. */
export function ShiftPolicySettings() {
  const t = useTranslations('shiftEvidence')
  const errors = useTranslations('error')
  const id = useId()
  const [policy, setPolicy] = useState<ShiftPolicy | null>(null)
  const [minutes, setMinutes] = useState('5')
  const [enabled, setEnabled] = useState(false)
  const [proof, setProof] = useState(false)
  const [pending, setPending] = useState(false)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [saved, setSaved] = useState(false)

  const load = useCallback(
    async (signal?: AbortSignal) => {
      setLoading(true)
      setError('')
      try {
        const { policy: result } = await fetchShiftPolicy(signal)
        if (signal?.aborted) return
        setPolicy(result)
        setEnabled(result.location_interval_seconds > 0)
        setMinutes(
          String(result.location_interval_seconds > 0 ? result.location_interval_seconds / 60 : 5),
        )
        setProof(result.proof_of_work_required)
      } catch (cause) {
        if (signal?.aborted) return
        setError(cause instanceof ApiError ? errors(cause.messageKey) : errors('server'))
      } finally {
        if (!signal?.aborted) setLoading(false)
      }
    },
    [errors],
  )

  useEffect(() => {
    const controller = new AbortController()
    void load(controller.signal)
    return () => controller.abort()
  }, [load])

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!policy || pending) return
    setSaved(false)
    const interval = enabled ? Number(minutes) * 60 : 0
    if (enabled && (!Number.isInteger(interval) || interval < 60 || interval > 86400)) {
      setError(t('invalidInterval'))
      return
    }
    setPending(true)
    setError('')
    try {
      const { policy: result } = await saveShiftPolicy({
        location_interval_seconds: interval,
        proof_of_work_required: proof,
      })
      setPolicy(result)
      setEnabled(result.location_interval_seconds > 0)
      setMinutes(
        String(result.location_interval_seconds > 0 ? result.location_interval_seconds / 60 : 5),
      )
      setProof(result.proof_of_work_required)
      setSaved(true)
    } catch (cause) {
      setError(cause instanceof ApiError ? errors(cause.messageKey) : errors('server'))
    } finally {
      setPending(false)
    }
  }

  return (
    <ListPanel title={t('heading')} note={t('scope')} padded>
      {loading ? (
        <p role="status">{t('loading')}</p>
      ) : policy ? (
        <form className="auth-form" onSubmit={submit} onChange={() => setSaved(false)}>
          <Field id={`${id}-location`} label={t('location')} help={t('locationHint')}>
            <select
              value={enabled ? 'on' : 'off'}
              onChange={(event) => setEnabled(event.target.value === 'on')}
              disabled={pending}
            >
              <option value="off">{t('off')}</option>
              <option value="on">{t('on')}</option>
            </select>
          </Field>
          {enabled && (
            <Field id={`${id}-interval`} label={t('interval')} help={t('intervalHint')}>
              <input
                type="number"
                min="1"
                max="1440"
                step="any"
                required
                value={minutes}
                onChange={(event) => setMinutes(event.target.value)}
                disabled={pending}
              />
            </Field>
          )}
          <Field id={`${id}-proof`} label={t('proof')} help={t('proofHint')}>
            <select
              value={proof ? 'on' : 'off'}
              onChange={(event) => setProof(event.target.value === 'on')}
              disabled={pending}
            >
              <option value="off">{t('off')}</option>
              <option value="on">{t('required')}</option>
            </select>
          </Field>
          <p className="field-hint">{t('startsNextShift')}</p>
          <div className="form-actions">
            <button className="btn btn-primary" type="submit" disabled={pending}>
              {pending ? t('saving') : t('save')}
            </button>
          </div>
          <p role="status" className="form-status">
            {saved ? t('saved') : ''}
          </p>
        </form>
      ) : (
        <button type="button" className="btn btn-ghost" onClick={() => void load()}>
          {t('retry')}
        </button>
      )}
      <p role="alert" className="form-error">
        {error}
      </p>
    </ListPanel>
  )
}
