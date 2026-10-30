# 2. The webhook validates synchronously, then processes fire-and-forget — no retry queue

## Status

Accepted (initial build).

## Context

A webhook sender (the thing POSTing a message to `/webhooks/inbound`) is usually
an at-least-once delivery system with its own retry/backoff policy, and
it expects the receiving endpoint to answer fast — holding the
connection open through an AI call plus several database writes risks
the sender's own timeout firing and redelivering a message that
actually succeeded. At the same time, a malformed payload (missing
sender, unparseable fields) is a problem the sender itself should find
out about, not something to silently drop.

## Decision

`WebhookController.inbound/2` validates the normalized payload
synchronously (`Tickets.change_new_ticket/2`, no database write yet) and
returns 422 immediately if it's invalid — the sender's own retry logic
gets a real answer to act on. Once validation passes, the actual
pipeline (`Tickets.receive/1`, which persists the ticket and runs
`Pipeline.process/1`) runs inside a detached `Task.Supervisor.start_child/2`
call, and the controller responds 200 immediately, without waiting for
that task to finish.

## Alternatives considered

- **Enqueue a real background job (Oban) instead of a bare `Task`.**
  This is genuinely the better answer for production — a crashed run
  gets retried automatically instead of silently dropped, which the
  `Task`-based version cannot do. It's called out directly in
  `WebhookController`'s own doc comment as the natural next step; it
  wasn't added because this app has no other use for a job queue yet,
  and introducing one for a single call site would be exactly the kind
  of complexity this app's conventions ask not to add without a real
  need for it.
- **Process synchronously and make the sender wait.** Simplest to
  reason about, but ties the webhook's response time to however long
  the AI call takes, and risks exactly the sender-timeout-triggers-a-
  redundant-retry problem this design avoids.

## Consequences

- A crash inside the detached `Task` (as opposed to a normal `{:error,
  reason}` return, which `Tickets.receive/1` already handles) is lost —
  there's no supervisor watching for it and no retry. This is a real,
  acknowledged gap, not an oversight: see the "what I'd do next" note on
  replacing this with Oban.
- The sender gets a fast, honest answer either way: 422 with the
  specific validation errors for a malformed payload, 200 the instant a
  well-formed one is accepted for processing — never a response that
  depends on how long the AI call or the database writes take.
- Validating before accepting means a sender's bug (a malformed payload)
  surfaces immediately and visibly in their own logs, rather than being
  silently absorbed and only discoverable by someone looking at this
  app's own error logs later.
