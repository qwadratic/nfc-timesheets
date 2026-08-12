#!/usr/bin/env node
/**
 * The design system, enforced. `backlog/docs/DESIGN-SYSTEM.md` is the prose; this file is
 * the part that can fail.
 *
 * Five rules, all mechanical, all about things that have already gone wrong here:
 *
 *   1. Every colour lives in `:root`. A hex inside a rule cannot be contrast-checked by
 *      anything, which is how ten of them ended up unmeasured.
 *   2. Every pinned pair clears its WCAG minimum, RECOMPUTED from the stylesheet rather
 *      than read off a table in a document. Text ≥ 4.5:1, a control's own boundary ≥ 3:1
 *      (1.4.11 — an input whose only border was #d8dce3 at 1.38:1 had, for a low-vision
 *      reader, no border at all).
 *   3. `overflow-wrap: anywhere` appears ONLY on the code chip. On a table cell it counts
 *      toward min-content width and crushes every text column to about 1ch — measured at
 *      1.95x on /workers/, UX-AUDIT finding 3, and it is invisible until somebody looks at
 *      a screenshot.
 *   4. Only `opacity` and `transform` are transitioned. Anything else either costs layout
 *      on every frame or fights the phone card transform.
 *   5. The `prefers-reduced-motion` block is the global `*` one, not a hand-maintained list
 *      of selectors — a list goes stale silently, and only for the people who need it.
 *
 * Plain node, no dependency (decision-16). Run: `node scripts/check-design-tokens.mjs`.
 * Exits non-zero on failure.
 *
 * MUTATION PROOF — a check whose negative case cannot fail is not a check. Each rule below
 * names the single edit that must turn it RED; `--self-test` performs all of them against
 * an in-memory copy and fails if any of them stays GREEN.
 */

import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const CSS_PATH = join(ROOT, 'app/globals.css')

/** Comments carry example hexes and prose about `anywhere`; only real CSS is checked. */
function stripComments(css) {
  return css.replace(/\/\*[\s\S]*?\*\//g, '')
}

/** The FIRST `:root` block, which is where the tokens live. */
function rootBlocks(css) {
  const blocks = []
  const re = /:root\s*\{([^}]*)\}/g
  let match = re.exec(css)
  while (match !== null) {
    blocks.push(match[1])
    match = re.exec(css)
  }
  return blocks
}

function tokens(css) {
  const map = new Map()
  for (const block of rootBlocks(stripComments(css))) {
    const re = /(--[a-z0-9-]+)\s*:\s*([^;]+);/g
    let match = re.exec(block)
    while (match !== null) {
      map.set(match[1], match[2].trim())
      match = re.exec(block)
    }
  }
  return map
}

/** WCAG 2.1 relative luminance, from sRGB. */
function luminance(hex) {
  const value = hex.replace('#', '')
  const full =
    value.length === 3
      ? value
          .split('')
          .map((c) => c + c)
          .join('')
      : value
  const channel = (i) => {
    const srgb = Number.parseInt(full.slice(i * 2, i * 2 + 2), 16) / 255
    return srgb <= 0.03928 ? srgb / 12.92 : ((srgb + 0.055) / 1.055) ** 2.4
  }
  return 0.2126 * channel(0) + 0.7152 * channel(1) + 0.0722 * channel(2)
}

export function contrast(a, b) {
  const [x, y] = [luminance(a), luminance(b)].sort((p, q) => q - p)
  return (x + 0.05) / (y + 0.05)
}

// Runnable check of the only arithmetic in this file, against the two ratios everybody
// knows by heart.
assert.equal(Math.round(contrast('#000000', '#ffffff')), 21)
assert.equal(contrast('#ffffff', '#ffffff'), 1)

/**
 * The pinned pairs. `min` is what WCAG demands of THAT pair, not a house style:
 * 4.5 for body text, 3.0 for the visual boundary of a control (1.4.11).
 */
const PAIRS = [
  ['--ink', '--bg-surface', 4.5],
  ['--ink', '--bg-app', 4.5],
  ['--ink-muted', '--bg-surface', 4.5],
  ['--ink-muted', '--bg-app', 4.5],
  ['--accent', '--bg-surface', 4.5],
  ['--ink-inverse', '--accent', 4.5],
  ['--ink-inverse', '--danger', 4.5],
  ['--accent-ink', '--accent-soft', 4.5],
  ['--caution-ink', '--caution-soft', 4.5],
  ['--state-amended-ink', '--state-amended-bg', 4.5],
  ['--danger', '--bg-surface', 4.5],
  ['--danger', '--danger-soft', 4.5],
  ['--ok', '--bg-surface', 4.5],
  ['--ok', '--ok-soft', 4.5],
  ['--caution', '--bg-surface', 4.5],
  // Non-text: these two identify a control or its focus and only need 3:1.
  ['--border-strong', '--bg-surface', 3.0],
  ['--border-strong', '--bg-app', 3.0],
  ['--border-focus', '--bg-surface', 3.0],
]

const RULES = [
  {
    name: 'every colour literal lives in :root',
    // MUTATION: move any hex into a rule body → RED.
    run(css) {
      const bare = stripComments(css)
      const inRoot = new Set()
      for (const block of rootBlocks(bare)) {
        for (const hit of block.match(/#[0-9a-fA-F]{3,8}\b/g) ?? []) inRoot.add(hit)
      }
      const withoutRoot = bare.replace(/:root\s*\{[^}]*\}/g, '')
      const offenders = withoutRoot.match(/#[0-9a-fA-F]{3,8}\b/g) ?? []
      assert.deepEqual(
        offenders,
        [],
        `hex outside :root: ${offenders.join(', ')} (known tokens: ${[...inRoot].length})`,
      )
    },
  },
  {
    name: 'every pinned pair clears its WCAG minimum (recomputed, not asserted)',
    // MUTATION: --ink-muted: #9aa1ab (2.61:1) or --border-strong: #d8dce3 → RED.
    run(css) {
      const map = tokens(css)
      const failures = []
      for (const [ink, bg, min] of PAIRS) {
        const a = map.get(ink)
        const b = map.get(bg)
        assert.ok(a !== undefined, `missing token ${ink}`)
        assert.ok(b !== undefined, `missing token ${bg}`)
        assert.ok(a.startsWith('#'), `${ink} is not a literal colour: ${a}`)
        assert.ok(b.startsWith('#'), `${bg} is not a literal colour: ${b}`)
        const ratio = contrast(a, b)
        if (ratio < min) failures.push(`${ink} on ${bg} = ${ratio.toFixed(2)} < ${min}`)
      }
      assert.deepEqual(failures, [], failures.join('; '))
    },
  },
  {
    name: '`overflow-wrap: anywhere` is scoped to the code chip and nothing else',
    // MUTATION: add `overflow-wrap: anywhere` to `.data-table td` → RED. This is finding 3.
    run(css) {
      const bare = stripComments(css)
      const count = (bare.match(/overflow-wrap:\s*anywhere/g) ?? []).length
      assert.equal(count, 1, `expected exactly one \`overflow-wrap: anywhere\`, found ${count}`)
      const chip = /\.code-inline,\s*\.code-block\s*\{[^}]*overflow-wrap:\s*anywhere/m
      assert.ok(chip.test(bare), 'the one `anywhere` is not the .code-inline/.code-block rule')
    },
  },
  {
    name: 'only opacity and transform are transitioned',
    // MUTATION: `transition: background 200ms` anywhere → RED.
    run(css) {
      const bare = stripComments(css)
      const allowed = new Set(['opacity', 'transform', 'none'])
      const offenders = []
      const re = /transition:\s*([^;]+);/g
      let match = re.exec(bare)
      while (match !== null) {
        const property = match[1].trim().split(/\s+/)[0]
        if (!allowed.has(property)) offenders.push(match[1].trim())
        match = re.exec(bare)
      }
      assert.deepEqual(offenders, [], `transitions on layout/paint properties: ${offenders}`)
    },
  },
  {
    name: 'prefers-reduced-motion turns motion OFF globally, not selector by selector',
    // MUTATION: replace `*, *::before, *::after` with `.skip-link` → RED. A scoped list is
    // what was there before, and it goes stale invisibly.
    run(css) {
      const bare = stripComments(css)
      const block = bare.match(
        /@media\s*\(prefers-reduced-motion:\s*reduce\)\s*\{([\s\S]*?\})\s*\}/,
      )
      assert.ok(block !== null, 'no prefers-reduced-motion block at all')
      assert.ok(
        /\*\s*,\s*\*::before\s*,\s*\*::after/.test(block[1]),
        'the reduced-motion block does not target `*, *::before, *::after`',
      )
      assert.ok(
        /transition-duration:\s*0\.01ms\s*!important/.test(block[1]),
        'the reduced-motion block does not force transition-duration',
      )
    },
  },
]

/** Each mutation must turn its own rule RED. A green mutant means the rule is decorative. */
const MUTANTS = [
  [
    'every colour literal lives in :root',
    (css) => css.replace('.form-error {', '.form-error {\n  color: #a4262c;'),
  ],
  [
    'every pinned pair clears its WCAG minimum (recomputed, not asserted)',
    (css) => css.replace('--ink-muted: #5b6472;', '--ink-muted: #9aa1ab;'),
  ],
  [
    'every pinned pair clears its WCAG minimum (recomputed, not asserted)',
    (css) => css.replace('--border-strong: #868d97;', '--border-strong: #d8dce3;'),
  ],
  [
    '`overflow-wrap: anywhere` is scoped to the code chip and nothing else',
    (css) =>
      css.replace(
        '  overflow-wrap: break-word;\n  hyphens: auto;',
        '  overflow-wrap: anywhere;\n  hyphens: auto;',
      ),
  ],
  [
    'only opacity and transform are transitioned',
    (css) =>
      css.replace(
        'transition: opacity var(--motion-fast) var(--ease-out);',
        'transition: background 200ms ease;',
      ),
  ],
  [
    'prefers-reduced-motion turns motion OFF globally, not selector by selector',
    (css) =>
      css.replace(
        '  *,\n  *::before,\n  *::after {\n    animation-duration',
        '  .skip-link {\n    animation-duration',
      ),
  ],
]

function main() {
  const css = readFileSync(CSS_PATH, 'utf8')
  const failures = []

  for (const rule of RULES) {
    try {
      rule.run(css)
      process.stdout.write(`  ok   ${rule.name}\n`)
    } catch (error) {
      failures.push(rule.name)
      process.stdout.write(`  FAIL ${rule.name}\n         ${error.message}\n`)
    }
  }

  if (process.argv.includes('--self-test')) {
    process.stdout.write('\n  mutation proofs (each must go RED):\n')
    for (const [target, mutate] of MUTANTS) {
      const mutated = mutate(css)
      if (mutated === css) {
        failures.push(`mutant for "${target}" changed nothing`)
        process.stdout.write(`  FAIL mutant did not apply: ${target}\n`)
        continue
      }
      const rule = RULES.find((r) => r.name === target)
      let red = false
      try {
        rule.run(mutated)
      } catch {
        red = true
      }
      if (red) process.stdout.write(`  ok   RED: ${target}\n`)
      else {
        failures.push(`mutant survived: ${target}`)
        process.stdout.write(`  FAIL GREEN under mutation (the rule proves nothing): ${target}\n`)
      }
    }
  }

  if (failures.length > 0) {
    process.stdout.write(`\n${failures.length} design-token check(s) failed.\n`)
    process.exitCode = 1
    return
  }
  process.stdout.write('\nAll design-token checks passed.\n')
}

main()
