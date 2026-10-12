'use client'

import { useFormatter, useTranslations } from 'next-intl'
import { useEffect, useState } from 'react'
import { ApiError } from '@/lib/api'
import { fetchShiftEvidence, type ShiftEvidence, shiftProofUrl } from '@/lib/shiftEvidence'

export function ShiftEvidenceDetails({ uuid }: { uuid: string }) {
  const t = useTranslations('shiftEvidence')
  const errors = useTranslations('error')
  const format = useFormatter()
  const [open, setOpen] = useState(false)
  const [data, setData] = useState<ShiftEvidence | null>(null)
  const [error, setError] = useState('')
  const [revision, setRevision] = useState(0)
  // biome-ignore lint/correctness/useExhaustiveDependencies: explicit retry and refresh trigger.
  useEffect(() => {
    if (!open) return
    const controller = new AbortController()
    setData(null)
    setError('')
    void fetchShiftEvidence(uuid, controller.signal)
      .then((result) => {
        if (!controller.signal.aborted) setData(result)
      })
      .catch((cause) => {
        if (!controller.signal.aborted)
          setError(cause instanceof ApiError ? errors(cause.messageKey) : errors('server'))
      })
    return () => controller.abort()
  }, [uuid, open, errors, revision])
  const time = (value: string) =>
    format.dateTime(new Date(value), {
      dateStyle: 'medium',
      timeStyle: 'short',
      timeZone: 'Europe/Vienna',
    })
  return (
    <details className="callout" onToggle={(event) => setOpen(event.currentTarget.open)}>
      <summary>{t('viewEvidence')}</summary>
      {open && (
        <>
          <p role="alert" className="form-error">
            {error}
          </p>
          {!data && !error && <p role="status">{t('loadingEvidence')}</p>}
          {data && (
            <>
              <p>{data.shift.proof_of_work_required ? t('photoRequired') : t('photoOptional')}</p>
              {data.proof ? (
                <p>
                  <a
                    className="link"
                    href={shiftProofUrl(uuid, data.proof.id)}
                    target="_blank"
                    rel="noreferrer"
                  >
                    {t('openPhoto')}
                  </a>
                  {' · '}
                  {time(data.proof.captured_at)}
                </p>
              ) : (
                <p>{t('noPhoto')}</p>
              )}
              <p>{t('positions', { count: data.samples.length })}</p>
              {data.samples.length > 0 && (
                <div className="table-scroll" style={{ maxHeight: '20rem', overflow: 'auto' }}>
                  <table className="data-table">
                    <thead>
                      <tr>
                        <th>{t('capturedAt')}</th>
                        <th>{t('coordinates')}</th>
                        <th>{t('accuracy')}</th>
                      </tr>
                    </thead>
                    <tbody>
                      {data.samples.map((sample) => (
                        <tr key={sample.sample_uuid}>
                          <td>{time(sample.captured_at)}</td>
                          <td>
                            {format.number(sample.latitude, { maximumFractionDigits: 6 })},{' '}
                            {format.number(sample.longitude, { maximumFractionDigits: 6 })}
                          </td>
                          <td>
                            {t('meters', {
                              value: format.number(sample.accuracy_m, { maximumFractionDigits: 0 }),
                            })}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </>
          )}
          <button
            type="button"
            className="btn btn-ghost"
            onClick={() => setRevision((value) => value + 1)}
          >
            {t('refreshEvidence')}
          </button>
        </>
      )}
    </details>
  )
}
