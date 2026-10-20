'use client'

import { type ReactNode, useEffect, useRef } from 'react'

/** Optional fields stay mounted; a failed validation always reveals its fields. */
export function FormDetails({
  title,
  errors,
  children,
}: {
  title: string
  errors?: Record<string, unknown>
  children: ReactNode
}) {
  const ref = useRef<HTMLDetailsElement>(null)
  useEffect(() => {
    if (errors && Object.values(errors).some(Boolean) && ref.current) ref.current.open = true
  }, [errors])
  return (
    <details className="form-details" ref={ref}>
      <summary>{title}</summary>
      <div className="form-details-body">{children}</div>
    </details>
  )
}
