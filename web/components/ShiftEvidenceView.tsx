'use client'

import { useFormatter, useTranslations } from 'next-intl'
import { useEffect, useId, useState } from 'react'
import { ShiftEvidenceMap } from '@/components/ShiftEvidenceMap'
import { ApiError } from '@/lib/api'
import { fetchShiftEvidence, type ShiftEvidence, shiftProofUrl } from '@/lib/shiftEvidence'
import { BUSINESS_TIME_ZONE } from '@/lib/shifts'
import { useOverlay } from '@/lib/useOverlay'

/** Whose shift this is, when the page holds the row. A deep link may arrive without it. */
export type ShiftEvidenceContext = {
  worker: string
  location: string
  start: string
  end: string | null
}

export type ShiftEvidenceViewProps = {
  /** The shift's `client_uuid` — the key the evidence route takes. */
  uuid: string
  context: ShiftEvidenceContext | null
  onClose: () => void
  /**
   * Offered only when `context` is null, i.e. the shift is not in the loaded page: puts the
   * log on that one shift (`?shift=<id>&period=all`) so the reader can see and correct it.
   */
  onShowInLog?: (shiftId: number) => void
}

/**
 * „Foto & GPS" — what the worker's phone proved about one shift, in one look: the camera
 * photo LARGE and inline, and the GPS samples as a trail on a map. Opened from the row's own
 * button, from the correction drawer, and from `?evidence=<client_uuid>` (the deep link).
 *
 * A wide centred dialog rather than <Modal> (which is deliberately small) or <Drawer> (440px:
 * no room for a photo beside a map). Same focus contract as both — lib/useOverlay.ts — and
 * the same `.modal` frame, widened by `.shift-evidence-modal`. Opened above the correction
 * drawer it is the innermost overlay, so Escape closes it and leaves the drawer standing.
 */
export function ShiftEvidenceView({ uuid, context, onClose, onShowInLog }: ShiftEvidenceViewProps) {
  const t = useTranslations('shiftEvidence')
  const tOverlay = useTranslations('overlay')
  const errors = useTranslations('error')
  const format = useFormatter()
  const titleId = useId()
  const ref = useOverlay<HTMLDivElement>(true, onClose)

  const [data, setData] = useState<ShiftEvidence | null>(null)
  const [error, setError] = useState('')
  const [revision, setRevision] = useState(0)
  const [photoFailed, setPhotoFailed] = useState(false)

  // The page keys this component by uuid, so `data` starts null per shift. A refresh keeps
  // the previous answer on screen until the new one lands: clearing it would unmount the map
  // and the next mount is a second billed map load for the same trail.
  // biome-ignore lint/correctness/useExhaustiveDependencies: `revision` is the explicit refresh trigger.
  useEffect(() => {
    const controller = new AbortController()
    setError('')
    setPhotoFailed(false)
    void fetchShiftEvidence(uuid, controller.signal)
      .then((result) => {
        if (!controller.signal.aborted) setData(result)
      })
      .catch((cause) => {
        if (controller.signal.aborted) return
        setError(cause instanceof ApiError ? errors(cause.messageKey) : errors('server'))
      })
    return () => controller.abort()
  }, [uuid, errors, revision])

  const dateTime = (iso: string) =>
    format.dateTime(new Date(iso), {
      dateStyle: 'medium',
      timeStyle: 'short',
      timeZone: BUSINESS_TIME_ZONE,
    })
  const timeOnly = (iso: string) =>
    format.dateTime(new Date(iso), {
      hour: '2-digit',
      minute: '2-digit',
      timeZone: BUSINESS_TIME_ZONE,
    })

  const contextLine =
    context === null
      ? data === null
        ? null
        : t('shiftNumber', { id: data.shift.id })
      : `${t('contextWho', { worker: context.worker, location: context.location })} · ${
          context.end === null
            ? t('contextRunning', { from: dateTime(context.start) })
            : t('contextWhen', { from: dateTime(context.start), to: dateTime(context.end) })
        }`

  const samples = data?.samples ?? []
  const first = samples[0]
  const last = samples[samples.length - 1]
  const photoUrl = data?.proof ? shiftProofUrl(uuid, data.proof.id) : null

  return (
    <>
      <button type="button" className="scrim" tabIndex={-1} aria-hidden="true" onClick={onClose} />
      <div
        ref={ref}
        className="modal shift-evidence-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        aria-busy={(data === null && error === '') || undefined}
        tabIndex={-1}
      >
        <header className="shift-evidence-header">
          <div>
            {contextLine === null ? null : <p className="step">{contextLine}</p>}
            <h2 id={titleId}>{t('dialogTitle')}</h2>
          </div>
          <button type="button" className="btn btn-quiet" onClick={onClose}>
            <span aria-hidden="true">✕</span>
            <span className="visually-hidden">{tOverlay('close')}</span>
          </button>
        </header>

        <div className="body">
          {error === '' ? null : (
            <p role="alert" className="form-error">
              {error}
            </p>
          )}
          {data === null && error === '' ? <p role="status">{t('loadingEvidence')}</p> : null}

          {data === null ? null : (
            <div className="shift-evidence-grid">
              <section className="shift-evidence-photo" aria-labelledby={`${titleId}-photo`}>
                <h3 id={`${titleId}-photo`}>{t('photoHeading')}</h3>
                {photoUrl !== null && data.proof !== null && !photoFailed ? (
                  <figure>
                    <a
                      href={photoUrl}
                      target="_blank"
                      rel="noreferrer"
                      className="shift-evidence-photo-link"
                    >
                      {/* biome-ignore lint/performance/noImgElement: decision-16 makes this a static export with no image optimizer, and the photo is an authenticated API response, not a build asset. */}
                      <img
                        src={photoUrl}
                        alt={t('photoAlt', { time: dateTime(data.proof.captured_at) })}
                        onError={() => setPhotoFailed(true)}
                      />
                      <span className="visually-hidden"> {t('photoOpenFull')}</span>
                    </a>
                    <figcaption>
                      {t('photoTaken', { time: dateTime(data.proof.captured_at) })}
                      {' · '}
                      <a className="link" href={photoUrl} target="_blank" rel="noreferrer">
                        {t('photoOpenFull')}
                      </a>
                    </figcaption>
                  </figure>
                ) : photoFailed ? (
                  <p className="callout">{t('photoFailed')}</p>
                ) : data.shift.proof_of_work_required ? (
                  <p className="callout shift-evidence-missing">{t('photoMissingRequired')}</p>
                ) : (
                  <p className="callout">{t('noPhoto')}</p>
                )}
                <p className="shift-evidence-note">
                  {data.shift.proof_of_work_required ? t('photoRequired') : t('photoOptional')}
                </p>
              </section>

              <section className="shift-evidence-trail" aria-labelledby={`${titleId}-trail`}>
                <h3 id={`${titleId}-trail`}>{t('mapHeading')}</h3>
                <p className="shift-evidence-note">
                  {t('positions', { count: samples.length })}
                  {first !== undefined && last !== undefined
                    ? ` · ${t('mapSpan', {
                        from: timeOnly(first.captured_at),
                        to: timeOnly(last.captured_at),
                      })}`
                    : null}
                </p>
                <ShiftEvidenceMap samples={samples} />
                {samples.length > 0 ? (
                  <details className="shift-evidence-samples">
                    <summary>{t('samplesList', { count: samples.length })}</summary>
                    <div className="table-scroll">
                      <table className="data-table">
                        <thead>
                          <tr>
                            <th scope="col">{t('capturedAt')}</th>
                            <th scope="col">{t('coordinates')}</th>
                            <th scope="col">{t('accuracy')}</th>
                          </tr>
                        </thead>
                        <tbody>
                          {samples.map((sample) => (
                            <tr key={sample.sample_uuid}>
                              <td>{dateTime(sample.captured_at)}</td>
                              <td>
                                {format.number(sample.latitude, { maximumFractionDigits: 6 })},{' '}
                                {format.number(sample.longitude, { maximumFractionDigits: 6 })}
                              </td>
                              <td>
                                {t('meters', {
                                  value: format.number(sample.accuracy_m, {
                                    maximumFractionDigits: 0,
                                  }),
                                })}
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </details>
                ) : null}
              </section>
            </div>
          )}
        </div>

        <footer>
          {context === null && data !== null && onShowInLog ? (
            <button
              type="button"
              className="btn btn-ghost"
              onClick={() => onShowInLog(data.shift.id)}
            >
              {t('showInLog')}
            </button>
          ) : null}
          <button
            type="button"
            className="btn btn-ghost"
            onClick={() => setRevision((value) => value + 1)}
          >
            {t('refreshEvidence')}
          </button>
          <button type="button" className="btn btn-primary" onClick={onClose}>
            {tOverlay('close')}
          </button>
        </footer>
      </div>
    </>
  )
}
