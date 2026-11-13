'use client'

import { useFormatter, useTranslations } from 'next-intl'
import { useEffect, useRef, useState } from 'react'
import {
  failureOf,
  type GMap,
  type GMarker,
  type GoogleMapsApi,
  loadGoogleMaps,
  MAPS_API_KEY,
  type MapFailure,
  mapStyleFor,
  onMapsAuthFailure,
  VIENNA_CENTRE,
} from '@/lib/map'
import type { ShiftSample } from '@/lib/shiftEvidence'
import { BUSINESS_TIME_ZONE } from '@/lib/shifts'

/**
 * ONE SHIFT'S GPS TRAIL: a marker per sample the worker's phone sent, joined in time order.
 *
 * Same loader, same failure vocabulary and same muted styles as components/HomeMap.tsx
 * (lib/map.ts) — no second map library and no second script tag. What it adds is the three
 * classes HomeMap never needed: `Polyline` (the walk), `InfoWindow` (the clicked sample) and
 * `SymbolPath` (vector dots, so start and end differ by colour AND by a letter, which
 * survives greyscale). They are typed here rather than in lib/map.ts because only this file
 * calls them.
 *
 * Every failure ends on a usable view: the photo beside it stays, and the parent's list of
 * samples carries the same times and coordinates as the markers.
 */

type GPolyline = { setMap(map: GMap | null): void }
type GInfoWindow = {
  setContent(content: Node): void
  open(options: { map: GMap; anchor: GMarker }): void
  close(): void
}
type TrailApi = GoogleMapsApi & {
  Polyline: new (options: Record<string, unknown>) => GPolyline
  InfoWindow: new (options?: Record<string, unknown>) => GInfoWindow
  SymbolPath: { CIRCLE: number; FORWARD_CLOSED_ARROW: number }
}

type TrailState = 'noKey' | 'empty' | 'loading' | 'ready' | 'blocked' | 'failed'

/**
 * Concrete colours, not tokens: Google draws these on its own canvas and does not read our
 * CSS variables (and does not parse `oklch()`). Mirrored by `.shift-evidence-dot-*` in
 * globals.css so the legend matches the markers exactly.
 */
export const TRAIL_COLOURS = { start: '#2fb36d', end: '#e5484d', point: '#4c8dff' } as const

/** One sample: a street corner, not a rooftop. */
const SINGLE_SAMPLE_ZOOM = 17
const FIT_PADDING = 48

function currentTheme(): 'dark' | 'light' {
  return document.documentElement.getAttribute('data-theme') === 'light' ? 'light' : 'dark'
}

export function ShiftEvidenceMap({ samples }: { samples: readonly ShiftSample[] }) {
  const t = useTranslations('shiftEvidence')
  const format = useFormatter()
  const containerRef = useRef<HTMLDivElement>(null)
  const mapRef = useRef<GMap | null>(null)
  const apiRef = useRef<TrailApi | null>(null)
  const drawnRef = useRef<{ setMap(map: GMap | null): void }[]>([])
  const infoRef = useRef<GInfoWindow | null>(null)
  const [state, setState] = useState<TrailState>('loading')
  const [failure, setFailure] = useState<MapFailure | null>(null)
  const [attempt, setAttempt] = useState(0)
  const hasSamples = samples.length > 0

  // Google's late rejection of the key: tear the map down, say why, keep the rest.
  // It can fire BEFORE the map's first `idle` (a bad key: the tiles never come, `idle` still
  // does), so it is remembered and `idle` may not overwrite it with „ready".
  const blockedRef = useRef(false)
  useEffect(
    () =>
      onMapsAuthFailure(() => {
        blockedRef.current = true
        setFailure('auth')
        setState('blocked')
      }),
    [],
  )

  /** Construct the map ONCE per mount — every `new Map` is a billed load. */
  // biome-ignore lint/correctness/useExhaustiveDependencies: `attempt` is the retry trigger; re-running this effect is the whole mechanism of "Karte erneut laden".
  useEffect(() => {
    // Nothing to draw comes first: „no key" would point at a list that is empty too.
    if (!hasSamples) {
      setState('empty')
      return
    }
    if (MAPS_API_KEY === '') {
      setState('noKey')
      return
    }
    if (mapRef.current !== null) return

    let cancelled = false
    setState('loading')
    setFailure(null)
    loadGoogleMaps()
      .then((loaded) => {
        const container = containerRef.current
        if (cancelled || container === null || mapRef.current !== null) return
        const api = loaded as TrailApi
        const map = new api.Map(container, {
          center: VIENNA_CENTRE,
          zoom: 13,
          styles: mapStyleFor(currentTheme()),
          gestureHandling: 'cooperative',
          disableDefaultUI: true,
          zoomControl: true,
          fullscreenControl: true,
          clickableIcons: false,
        })
        mapRef.current = map
        apiRef.current = api
        infoRef.current = new api.InfoWindow()
        map.addListener('click', () => infoRef.current?.close())
        api.event.addListenerOnce(map, 'idle', () => {
          if (!cancelled && !blockedRef.current) setState('ready')
        })
      })
      .catch((cause: unknown) => {
        if (cancelled) return
        setFailure(failureOf(cause))
        setState('failed')
      })
    return () => {
      cancelled = true
    }
  }, [hasSamples, attempt])

  /** Draw (and on a refresh, redraw) the trail, then fit the map to it. */
  useEffect(() => {
    const map = mapRef.current
    const api = apiRef.current
    if (state !== 'ready' || map === null || api === null) return

    for (const overlay of drawnRef.current) overlay.setMap(null)
    drawnRef.current = []
    infoRef.current?.close()

    const time = (iso: string) =>
      format.dateTime(new Date(iso), {
        hour: '2-digit',
        minute: '2-digit',
        timeZone: BUSINESS_TIME_ZONE,
      })
    const path = samples.map((sample) => ({ lat: sample.latitude, lng: sample.longitude }))

    if (path.length > 1) {
      drawnRef.current.push(
        new api.Polyline({
          map,
          path,
          strokeColor: TRAIL_COLOURS.point,
          strokeOpacity: 0.85,
          strokeWeight: 3,
          // Arrows along the line: the ORDER is the point of a trail, and a bare line does
          // not say which way the worker went.
          icons: [
            {
              icon: { path: api.SymbolPath.FORWARD_CLOSED_ARROW, scale: 2.5 },
              offset: '50px',
              repeat: '120px',
            },
          ],
        }),
      )
    }

    const last = samples.length - 1
    samples.forEach((sample, index) => {
      const role = index === 0 ? 'start' : index === last ? 'end' : 'point'
      const at = time(sample.captured_at)
      const label =
        role === 'start'
          ? t('markerStart', { time: at })
          : role === 'end'
            ? t('markerEnd', { time: at })
            : t('markerPoint', { index: index + 1, time: at })
      const accuracy = t('markerAccuracy', {
        value: format.number(sample.accuracy_m, { maximumFractionDigits: 0 }),
      })
      const big = role !== 'point'
      const marker = new api.Marker({
        map,
        position: path[index],
        // The native tooltip on hover: the time label without a click.
        title: `${label} · ${accuracy}`,
        zIndex: role === 'start' ? 3 : role === 'end' ? 4 : 1,
        icon: {
          path: api.SymbolPath.CIRCLE,
          scale: big ? 11 : 5,
          fillColor: TRAIL_COLOURS[role],
          fillOpacity: 1,
          strokeColor: '#ffffff',
          strokeWeight: 2,
        },
        label: big
          ? {
              text: role === 'start' ? t('markerStartLetter') : t('markerEndLetter'),
              color: '#ffffff',
              fontSize: '11px',
              fontWeight: '700',
            }
          : undefined,
      })
      marker.addListener('click', () => {
        // Built as DOM with textContent, never as an HTML string: nothing here is markup.
        const box = document.createElement('div')
        box.className = 'shift-evidence-infowindow'
        const heading = document.createElement('strong')
        heading.textContent = label
        const detail = document.createElement('div')
        detail.textContent = accuracy
        box.append(heading, detail)
        infoRef.current?.setContent(box)
        infoRef.current?.open({ map, anchor: marker })
      })
      drawnRef.current.push(marker)
    })

    const only = path.length === 1 ? path[0] : undefined
    if (only !== undefined) {
      map.setCenter(only)
      map.setZoom(SINGLE_SAMPLE_ZOOM)
    } else if (path.length > 1) {
      const bounds = new api.LatLngBounds()
      for (const point of path) bounds.extend(point)
      map.fitBounds(bounds, FIT_PADDING)
    }
  }, [samples, state, format, t])

  /** Theme switch: `setOptions`, never a remount. */
  useEffect(() => {
    const apply = () => mapRef.current?.setOptions({ styles: mapStyleFor(currentTheme()) })
    const observer = new MutationObserver(apply)
    observer.observe(document.documentElement, { attributeFilter: ['data-theme'] })
    return () => observer.disconnect()
  }, [])

  const message =
    state === 'noKey'
      ? t('mapNoKey')
      : state === 'empty'
        ? t('mapNoSamples')
        : state === 'loading'
          ? t('mapLoading')
          : state === 'blocked'
            ? t('mapBlocked')
            : state === 'failed'
              ? failure === 'timeout'
                ? t('mapTimeout')
                : failure === 'auth'
                  ? t('mapBlocked')
                  : t('mapNetwork')
              : ''
  const drawable = state === 'loading' || state === 'ready'

  return (
    <div className="shift-evidence-map-region">
      {/* Always mounted, so a retry never races its own box into existence; HIDDEN on every
          failure — never a grey rectangle under an error overlay. aria-hidden: the sample
          list beside it is the keyboard and screen-reader equivalent of every marker. */}
      <div
        ref={containerRef}
        className="shift-evidence-map"
        hidden={!drawable}
        aria-hidden="true"
      />
      <p
        role="status"
        className={drawable ? 'shift-evidence-map-status' : 'callout shift-evidence-map-status'}
      >
        {message}
      </p>
      {state === 'failed' ? (
        <button
          type="button"
          className="btn btn-ghost"
          onClick={() => setAttempt((value) => value + 1)}
        >
          {t('mapRetry')}
        </button>
      ) : null}
      {drawable && hasSamples ? (
        <ul className="shift-evidence-legend">
          <li>
            <span className="shift-evidence-dot shift-evidence-dot-start" aria-hidden="true">
              {t('markerStartLetter')}
            </span>
            {t('legendStart')}
          </li>
          <li>
            <span className="shift-evidence-dot shift-evidence-dot-end" aria-hidden="true">
              {t('markerEndLetter')}
            </span>
            {t('legendEnd')}
          </li>
          <li>
            <span className="shift-evidence-dot shift-evidence-dot-point" aria-hidden="true" />
            {t('legendPoint')}
          </li>
          <li>
            <span className="shift-evidence-line" aria-hidden="true" />
            {t('legendPath')}
          </li>
        </ul>
      ) : null}
    </div>
  )
}
