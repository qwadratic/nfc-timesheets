'use client'

import Link from 'next/link'
import { useTranslations } from 'next-intl'
import { type FormEvent, useEffect, useRef, useState } from 'react'
import { Field } from '@/components/Field'
import { useLocaleSetting } from '@/components/IntlProvider'
import { ShiftPolicySettings } from '@/components/ShiftPolicySettings'
import { useWorkspace } from '@/components/useWorkspace'
import { ApiError, saveLocation, saveWorker } from '@/lib/api'
import { parseEuroToCents } from '@/lib/money'
import { completedSetup, saveCompany } from '@/lib/workspaces'

export default function SetupPage() {
  const t = useTranslations('workspace')
  const errors = useTranslations('error')
  const { setLocale } = useLocaleSetting()
  const { data, error, loading, reload } = useWorkspace()
  const [step, setStep] = useState<number | null>(null)
  const [pending, setPending] = useState(false)
  const [feedback, setFeedback] = useState<{ name: string } | 'company' | null>(null)
  const [saveError, setSaveError] = useState('')
  const [address, setAddress] = useState('')
  const [names, setNames] = useState(['', '', ''])
  const [companyName, setCompanyName] = useState<string | null>(null)
  const [localeDraft, setLocaleDraft] = useState<'de' | 'en' | null>(null)
  const [rateDraft, setRateDraft] = useState('')
  const requestIds = useRef(['', '', ''])
  const nameInput = useRef<HTMLInputElement>(null)
  const done = data ? completedSetup(data) : [false, false, false, false]
  const current = step ?? (done.every(Boolean) ? 3 : done.findIndex((value) => !value))
  useEffect(() => {
    if (data && step === null)
      setStep(
        completedSetup(data).every(Boolean) ? 3 : completedSetup(data).findIndex((value) => !value),
      )
  }, [data, step])
  useEffect(() => {
    if (feedback && !loading) nameInput.current?.focus()
  }, [feedback, loading])

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    const name = String(form.get('name') ?? '')
    setPending(true)
    setSaveError('')
    setFeedback(null)
    if (!requestIds.current[current]) requestIds.current[current] = crypto.randomUUID()
    const requestId = requestIds.current[current] ?? ''
    try {
      if (current === 0) {
        const locale = form.get('locale') === 'en' ? 'en' : 'de'
        await saveCompany(name, locale)
        setLocale(locale)
      } else if (current === 1) {
        await saveLocation({
          request_id: requestId,
          slug: `site-${requestId}`,
          name,
          address,
          active: true,
        })
      } else if (current === 2) {
        const rate = parseEuroToCents(String(form.get('rate') ?? ''))
        if (rate === null || rate <= 0 || rate > 1000000) {
          setSaveError(t('invalidRate'))
          return
        }
        await saveWorker({
          request_id: requestId,
          name,
          hourly_rate_cents: rate,
          email: '',
          phone: '',
          active: true,
        })
      }
      requestIds.current[current] = ''
      setFeedback(current === 0 ? 'company' : { name })
      setNames((values) => values.map((value, index) => (index === current ? '' : value)))
      if (current === 1) setAddress('')
      if (current === 2) setRateDraft('')
      if (current === 0) setStep(1)
      reload()
    } catch (cause) {
      setSaveError(cause instanceof ApiError ? errors(cause.messageKey) : errors('server'))
    } finally {
      setPending(false)
    }
  }
  return (
    <div className="workspace-page setup-page">
      <header>
        <h1>{t('setupTitle')}</h1>
        <p className="lede">{t('setupIntro')}</p>
      </header>
      <p role="alert" className="form-error">
        {saveError || (error ? errors(error) : '')}
      </p>
      <p role="status">
        {feedback === 'company' ? t('saved') : feedback ? t('addedKeepGoing', feedback) : ''}
      </p>
      {loading && <p role="status">{t('loading')}</p>}
      {data && !loading && !error && (
        <>
          <ol className="setup-steps">
            {(['companyStep', 'locationsStep', 'workersStep', 'readyStep'] as const).map(
              (key, index) => (
                <li key={key}>
                  <button
                    type="button"
                    disabled={pending}
                    onClick={() => {
                      setStep(index)
                      setFeedback(null)
                      setSaveError('')
                    }}
                    aria-current={current === index ? 'step' : undefined}
                    className={done[index] ? 'is-done' : undefined}
                  >
                    <span className="setup-number" aria-hidden="true">
                      {done[index] ? (
                        <svg
                          aria-hidden="true"
                          width="14"
                          height="14"
                          viewBox="0 0 16 16"
                          fill="none"
                          stroke="currentColor"
                          strokeWidth="2.5"
                          strokeLinecap="round"
                          strokeLinejoin="round"
                        >
                          <path d="M3 8.5l3.2 3.2L13 4.8" />
                        </svg>
                      ) : (
                        index + 1
                      )}
                    </span>
                    <span>
                      {t(key)}
                      <small>
                        {index === 1
                          ? t('existingLocations', { count: data.setup.locations })
                          : index === 2
                            ? t('existingWorkers', { count: data.setup.workers })
                            : t(done[index] ? 'completed' : 'toDo')}
                      </small>
                    </span>
                  </button>
                </li>
              ),
            )}
          </ol>
          <section className="workspace-panel setup-content">
            {current < 3 ? (
              <form key={current} className="auth-form" onSubmit={submit}>
                <h2>
                  {t(
                    (['companyStep', 'locationsStep', 'workersStep'] as const)[current] ??
                      'companyStep',
                  )}
                </h2>
                <p>
                  {t(
                    (['companyHint', 'locationHint', 'workerHint'] as const)[current] ??
                      'companyHint',
                  )}
                </p>
                {current > 0 && (
                  <p className="workspace-note">
                    {t(current === 1 ? 'existingLocations' : 'existingWorkers', {
                      count: current === 1 ? data.setup.locations : data.setup.workers,
                    })}
                  </p>
                )}
                <Field
                  id="setup-name"
                  label={t(
                    current === 0 ? 'companyName' : current === 1 ? 'buildingName' : 'workerName',
                  )}
                >
                  <input
                    ref={nameInput}
                    name="name"
                    required
                    maxLength={current === 2 ? 120 : 160}
                    value={
                      current === 0 ? (companyName ?? data.company.name) : (names[current] ?? '')
                    }
                    onChange={(event) =>
                      current === 0
                        ? setCompanyName(event.target.value)
                        : setNames((values) =>
                            values.map((value, index) =>
                              index === current ? event.target.value : value,
                            ),
                          )
                    }
                    disabled={pending}
                    autoComplete={current === 0 ? 'organization' : 'off'}
                  />
                </Field>
                {current === 0 && (
                  <Field id="setup-locale" label={t('companyLanguage')}>
                    <select
                      name="locale"
                      value={localeDraft ?? data.company.locale}
                      onChange={(event) =>
                        setLocaleDraft(event.target.value === 'en' ? 'en' : 'de')
                      }
                      disabled={pending}
                    >
                      <option value="de">{t('german')}</option>
                      <option value="en">{t('english')}</option>
                    </select>
                  </Field>
                )}
                {current === 1 && (
                  <Field id="setup-address" label={t('address')} help={t('addressHint')}>
                    <input
                      value={address}
                      onChange={(event) => setAddress(event.target.value)}
                      required
                      maxLength={300}
                      autoComplete="street-address"
                      disabled={pending}
                    />
                  </Field>
                )}
                {current === 2 && (
                  <Field id="setup-rate" label={t('hourlyRate')} help={t('rateSetupHint')}>
                    <input
                      name="rate"
                      value={rateDraft}
                      onChange={(event) => setRateDraft(event.target.value)}
                      inputMode="decimal"
                      required
                      placeholder={t('ratePlaceholder')}
                      disabled={pending}
                    />
                  </Field>
                )}
                <div className="workspace-actions">
                  <button className="btn btn-primary" type="submit" disabled={pending}>
                    {pending
                      ? t('saving')
                      : t(
                          current === 0
                            ? 'saveContinue'
                            : current === 1
                              ? 'addBuilding'
                              : 'addWorker',
                        )}
                  </button>
                  {done[current] && (
                    <button
                      className="btn btn-ghost"
                      type="button"
                      disabled={pending}
                      onClick={() => {
                        setStep(Math.min(current + 1, 3))
                        setSaveError('')
                        setFeedback(null)
                      }}
                    >
                      {t(
                        current === 1
                          ? 'continueTeam'
                          : current === 2
                            ? 'continueAccess'
                            : 'continue',
                      )}
                    </button>
                  )}
                </div>
              </form>
            ) : (
              <>
                <h2>{t('readyTitle')}</h2>
                <p>{t('readyHint')}</p>
                <ul className="workspace-checklist">
                  {(
                    [
                      {
                        key: 'operatorCheck',
                        ready: data.setup.operators > 0,
                        href: '/operators/',
                      },
                      {
                        key: 'tagCheck',
                        ready: data.setup.verified_zones > 0,
                        href: '/locations/',
                      },
                      {
                        key: 'loginCheck',
                        ready: data.setup.joined_workers > 0,
                        href: '/workers/',
                      },
                      { key: 'shiftCheck', ready: data.setup.shifts > 0, href: '/shifts/' },
                    ] as const
                  ).map((item) => (
                    <li key={item.key}>
                      <span className={item.ready ? 'setup-status done' : 'setup-status'}>
                        {t(item.ready ? 'completed' : 'toDo')}
                      </span>
                      <div>
                        <h3>{t(item.key)}</h3>
                        <p>{t(`${item.key}Hint`)}</p>
                        <Link href={item.href}>{t(`${item.key}Action`)}</Link>
                      </div>
                    </li>
                  ))}
                </ul>
                {done[3] ? (
                  <Link className="btn btn-primary" href="/workspace/">
                    {t('openDashboard')}
                  </Link>
                ) : (
                  <button type="button" className="btn btn-ghost" onClick={reload}>
                    {t('checkAgain')}
                  </button>
                )}
              </>
            )}
          </section>
          {current === 0 && <ShiftPolicySettings />}
          <div className="workspace-actions">
            <Link href="/workspace/">{t('backOverview')}</Link>
            <span className="workspace-note">{t('resumeHint')}</span>
          </div>
        </>
      )}
    </div>
  )
}
