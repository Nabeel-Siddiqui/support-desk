# 3. The deterministic keyword fallback is the default, not a degraded mode

## Status

Accepted (initial build).

## Context

Ticket analysis (intent, sentiment, urgency, a one-line summary, a
confidence score) can come from an actual Claude tool-use call or from
plain keyword matching against the ticket's text. A real API call costs
money, needs a key, and can fail or time out; a test suite — and a
fresh clone with no key configured at all — still needs analysis to
happen, deterministically, every time.

## Decision

`AI.analyze/1` only attempts a real Claude call when both
`config :support_desk, :ai_enabled` is true *and* `ANTHROPIC_API_KEY`
is actually set in the environment; otherwise it runs
`fallback/2` directly. A real call that errors (timeout, malformed
response, rate limit) logs a warning and falls back too, rather than
returning an error to the caller. `AI_ENABLED` is never set in test
config, so the suite always exercises the same deterministic path —
no key needed, no network call possible, nothing to `Mox` around.

## Alternatives considered

- **Treat the fallback purely as an error-recovery path**, with the real
  AI call as the only "intended" behavior and the keyword matcher as a
  degraded mode that only exists for when something's broken. Rejected
  because it would make the fallback a second-class, lightly-tested
  path in practice (the one code path that *only* runs when something
  has already gone wrong is the one most likely to rot unnoticed) when
  it's actually the path the entire test suite exercises and the one
  anyone cloning this repo sees first, with no setup.
- **Require `ANTHROPIC_API_KEY` and fail fast if it's missing.** Matches
  how this app already treats the key when `AI_ENABLED` is explicitly
  turned on (boot fails fast — see the README's configuration table),
  but doing that unconditionally would mean the app can't run at all
  without an API key, which is the wrong default for a portfolio
  project meant to run locally in minutes.

## Consequences

- Cloning this repo and running `mix test` or `mix phx.server` never
  needs a Claude API key, and never makes a real network call — the
  same property every other AI-touching app in this portfolio holds for
  its own external service.
- A production deployment that wants real AI analysis opts in
  explicitly (`AI_ENABLED=true` plus the key) rather than it being
  silently on by default; forgetting the key when `AI_ENABLED` is set
  is a boot-time failure, not a silent fallback to keyword matching in
  production.
- The keyword fallback has to stay genuinely good on its own, not just
  "good enough to not crash" — it's graded as a first-class code path
  (its own module attributes listing the words per intent/sentiment/
  urgency, its own tests) specifically because of how often it actually
  runs.
