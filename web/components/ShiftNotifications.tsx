'use client'

import Link from 'next/link'
import { useFormatter, useTranslations } from 'next-intl'
import { useCallback, useEffect, useId, useRef, useState } from 'react'
import { ApiError } from '@/lib/api'
import {
  evidenceHref,
  fetchShiftNotifications,
  markShiftNotificationsSeen,
  SHIFT_NOTIFICATION_POLL_MS,
  type ShiftNotification,
  type ShiftNotificationFeed,
} from '@/lib/shiftNotifications'
import { BUSINESS_TIME_ZONE, durationMinutes, formatDuration } from '@/lib/shifts'

const TOAST_MS = 10_000

/**
 * TASK-380 — the bell in the header: "Schicht beendet: <worker> · <building> · <duration>"
 * with a direct „Nachweise ansehen" link to that shift's photo + GPS evidence.
 *
 * POLLING, NOT PUSH. Every 45 s while the tab is visible, and once immediately when it
 * becomes visible again; a hidden tab asks nothing. A 401 stops the loop — the session is
 * gone and every page already sends the director to the sign-in screen on its own.
 *
 * A TOAST only for a shift that ended WHILE this page was open: the first load just fills
 * the badge, otherwise every sign-in would greet the director with last night's shifts.
 *
 * Opening the panel marks read up to the newest row it SHOWS (never "now"). It is a
 * disclosure, like HeaderTools' settings: aria-expanded + aria-controls, Escape and an
 * outside click close it, no focus trap.
 */
export function ShiftNotifications() {
  const t = useTranslations('shiftNotifications')
  const format = useFormatter()
  const panelId = useId()
  const rootRef = useRef<HTMLDivElement>(null)
  const knownIds = useRef<Set<number> | null>(null)
  const [feed, setFeed] = useState<ShiftNotificationFeed | null>(null)
  const [failed, setFailed] = useState(false)
  const [open, setOpen] = useState(false)
  const [toast, setToast] = useState<{ item: ShiftNotification; more: number } | null>(null)

  const load = useCallback(async (signal?: AbortSignal): Promise<boolean> => {
    try {
      const next = await fetchShiftNotifications(signal)
      const known = knownIds.current
      if (known) {
        const fresh = next.notifications.filter((n) => n.unread && !known.has(n.id))
        const [first] = fresh
        if (first) setToast({ item: first, more: fresh.length - 1 })
      }
      knownIds.current = new Set([...(known ?? []), ...next.notifications.map((n) => n.id)])
      setFeed(next)
      setFailed(false)
      return true
    } catch (cause) {
      if (signal?.aborted) return true
      setFailed(true)
      return !(cause instanceof ApiError && cause.status === 401)
    }
  }, [])

  useEffect(() => {
    const controller = new AbortController()
    let stopped = false
    const tick = () => {
      if (stopped || document.visibilityState !== 'visible') return
      void load(controller.signal).then((keepGoing) => {
        if (!keepGoing) stopped = true
      })
    }
    tick()
    const timer = window.setInterval(tick, SHIFT_NOTIFICATION_POLL_MS)
    document.addEventListener('visibilitychange', tick)
    return () => {
      stopped = true
      controller.abort()
      window.clearInterval(timer)
      document.removeEventListener('visibilitychange', tick)
    }
  }, [load])

  useEffect(() => {
    if (!toast) return
    const timer = window.setTimeout(() => setToast(null), TOAST_MS)
    return () => window.clearTimeout(timer)
  }, [toast])

  useEffect(() => {
    if (!open) return
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setOpen(false)
    }
    const onPointerDown = (event: PointerEvent) => {
      if (rootRef.current && !rootRef.current.contains(event.target as Node)) setOpen(false)
    }
    document.addEventListener('keydown', onKeyDown, true)
    document.addEventListener('pointerdown', onPointerDown)
    return () => {
      document.removeEventListener('keydown', onKeyDown, true)
      document.removeEventListener('pointerdown', onPointerDown)
    }
  }, [open])

  // Read up to the newest row on screen, once the panel is open and something is unread.
  // Keyed on the cursor STRING, not the row object: every poll makes a new object, and during
  // an impersonation the server keeps the badge (decision-80), so an object key would loop.
  const newest = feed?.notifications[0]?.ended_at
  const unread = feed?.unread_count ?? 0
  useEffect(() => {
    if (!open || !newest || unread === 0) return
    const controller = new AbortController()
    // Only the COUNT is taken from the answer: the rows keep their „Neu" mark while the
    // panel the director is reading stays open; the next poll brings the read state.
    markShiftNotificationsSeen(newest, controller.signal)
      .then((next) =>
        setFeed((was) => was && { ...was, unread_count: next.unread_count, seen_at: next.seen_at }),
      )
      .catch(() => {
        // The badge simply stays; nothing is lost and the next open tries again.
      })
    return () => controller.abort()
  }, [open, newest, unread])

  const headline = (item: ShiftNotification) =>
    t('ended', {
      worker: item.worker_name,
      building: item.location_name,
      duration: t('duration', {
        value: formatDuration(durationMinutes(item.start_time, item.end_time)),
      }),
    })

  const proof = (item: ShiftNotification) =>
    [item.has_photo ? t('photo') : t('noPhoto'), t('samples', { count: item.sample_count })].join(
      ' · ',
    )

  return (
    <div className="shift-notifications" ref={rootRef}>
      <button
        type="button"
        className="btn btn-ghost shift-notifications-toggle"
        aria-expanded={open}
        aria-controls={panelId}
        aria-label={t('buttonLabel', { count: unread })}
        onClick={() => setOpen((was) => !was)}
      >
        <span aria-hidden="true">🔔</span>
        {unread > 0 ? (
          <span className="shift-notifications-badge" aria-hidden="true">
            {unread > 9 ? t('badgeOverflow') : unread}
          </span>
        ) : null}
      </button>

      <section
        className="shift-notifications-panel"
        id={panelId}
        hidden={!open}
        aria-label={t('title')}
      >
        <h2 className="shift-notifications-title">{t('title')}</h2>
        {failed && !feed ? <p role="status">{t('loadError')}</p> : null}
        {feed && feed.notifications.length === 0 ? <p>{t('empty')}</p> : null}
        {feed && feed.notifications.length > 0 ? (
          <ul className="shift-notifications-list">
            {feed.notifications.map((item) => (
              <li key={item.id} className={item.unread ? 'is-unread' : undefined}>
                <p className="shift-notifications-headline">
                  {item.unread ? <span className="shift-notifications-new">{t('new')}</span> : null}
                  {headline(item)}
                </p>
                <p className="shift-notifications-meta">
                  {t('endedAt', {
                    time: format.dateTime(new Date(item.end_time), {
                      dateStyle: 'short',
                      timeStyle: 'short',
                      timeZone: BUSINESS_TIME_ZONE,
                    }),
                  })}{' '}
                  · {proof(item)}
                </p>
                <Link
                  className="btn btn-ghost"
                  href={evidenceHref(item.client_uuid)}
                  onClick={() => setOpen(false)}
                >
                  {t('viewEvidence')}
                </Link>
              </li>
            ))}
          </ul>
        ) : null}
      </section>

      {/* Always in the DOM so the live region exists before the text arrives. */}
      <div className="shift-notifications-toast-region" role="status" aria-live="polite">
        {toast ? (
          <div className="shift-notifications-toast">
            <p>
              {headline(toast.item)}
              {toast.more > 0 ? ` ${t('toastMore', { count: toast.more })}` : null}
            </p>
            <div className="shift-notifications-toast-actions">
              <Link
                className="btn btn-primary"
                href={evidenceHref(toast.item.client_uuid)}
                onClick={() => setToast(null)}
              >
                {t('viewEvidence')}
              </Link>
              <button type="button" className="btn btn-ghost" onClick={() => setToast(null)}>
                {t('dismiss')}
              </button>
            </div>
          </div>
        ) : null}
      </div>
    </div>
  )
}
