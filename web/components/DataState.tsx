'use client'

import type { ReactNode } from 'react'

/**
 * The one region that says what happened instead of showing data: loading, empty, empty
 * because of a filter, or an error with a way out.
 *
 * The props are a DISCRIMINATED UNION, not four booleans, so „loading" and „error" cannot
 * both be passed (UX-AUDIT finding 1: every screen rendered exactly that pair after a 500,
 * and the loading text never went away). Four kinds, one at a time, by construction.
 *
 * Never a spinner and never a skeleton: the truth here is a word. A skeleton claims data is
 * coming, which is the one thing the error branch knows to be false.
 */
type Common = {
  /** One plain sentence. This is what the reader actually reads. */
  headline: string
  /** Optional second sentence: the fact that makes the headline actionable. */
  detail?: string
  /** Optional escape hatches. Real buttons and real links, never icon-only. */
  children?: ReactNode
}

export type DataStateProps = Common &
  (
    | { kind: 'loading' }
    | { kind: 'empty' }
    | { kind: 'filtered' }
    | { kind: 'error'; retryLabel: string; onRetry: () => void }
  )

export function DataState(props: DataStateProps) {
  const { kind, headline, detail, children } = props

  return (
    <div
      className={`data-state data-state-${kind}`}
      // Always in the DOM as a live region so a state change is announced as a TEXT change
      // inside an existing region rather than as a node blinking into existence.
      role={kind === 'error' ? 'alert' : 'status'}
      aria-live={kind === 'error' ? 'assertive' : 'polite'}
      // Removed on settle. Only `loading` is busy — an error is finished, not pending.
      aria-busy={kind === 'loading' ? true : undefined}
    >
      <p className="data-state-headline">{headline}</p>
      {detail === undefined ? null : <p>{detail}</p>}
      {/* The retry button is the FIRST focusable thing in the region, and focus is not
          moved here: a screen reader user mid-sentence must not be yanked. */}
      {props.kind === 'error' ? (
        <p className="button-row">
          <button type="button" className="button-primary" onClick={props.onRetry}>
            {props.retryLabel}
          </button>
        </p>
      ) : null}
      {children}
    </div>
  )
}
