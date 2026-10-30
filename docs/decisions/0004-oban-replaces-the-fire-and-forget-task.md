# 4. Oban replaces the fire-and-forget Task

## Status

Accepted. Supersedes the "no retry queue" half of
[ADR 2](0002-fire-and-forget-not-a-retry-queue.md).

## Context

[ADR 2](0002-fire-and-forget-not-a-retry-queue.md) named the gap in
its own "consequences" section: a crash inside the detached `Task` —
not an AI-call failure, which `Pipeline.process/1`'s own `rescue`
already turns into a `:failed` ticket, but something escaping that,
like the ticket's own `Repo.insert` hitting an unexpected error — was
silently lost. No supervisor watched for it, nothing retried it, and
the webhook sender had already gotten its 200. `WebhookController`'s
own doc comment called this out directly: "This is where Oban would
go instead." This app also had `Tickets.add_ticket/1`, used by the
dashboard's "new ticket" form, which calls `Pipeline.process/1`
synchronously — that path is unaffected by any of this and stays
exactly as it is, since an admin typing into a form expects to see
the routed result immediately, not get a receipt for later.

## Decision

`Pipeline.receive/1` now writes the ticket row and enqueues a
`ProcessTicketWorker` job in one `Ecto.Multi` transaction
(`Multi.insert` + `Oban.insert`), so a ticket can never exist without
a job queued for it, or vice versa. `WebhookController.inbound/2`
calls this directly and synchronously — no `Task` at all anymore. This
is fast enough to do inline (milliseconds: one `INSERT` into
`tickets`, one into `oban_jobs`) because the slow part, the actual
analyze -> match -> triage pipeline, moved into `ProcessTicketWorker`,
which Oban runs out of band. The webhook still answers instantly; what
changed is that the thing guaranteeing "instantly" is "this write is
fast," not "we didn't wait to find out if it worked."

## Alternatives considered

- **Keep the `Task`, just supervise it more carefully** (link it,
  trap exits, log on `:DOWN`). Narrows the silent-failure window but
  still has no retry and no persistence — a crash is still a crash,
  just a logged one instead of a silent one. Oban gets both retry and
  a durable job row for the same amount of code.
- **Enqueue the Oban job without the `Ecto.Multi`** (insert the ticket,
  then separately call `Oban.insert!/1`). Simpler to read, but
  reintroduces exactly the kind of gap this change closes: if the
  process dies between the two inserts, the ticket exists with no job
  queued for it, forever. The whole point of moving to Oban was to stop
  that class of problem from being possible, not just less likely.

## Consequences

- A crash anywhere in the pipeline — including ones `Pipeline.process/1`'s
  own `rescue` can't help with, like the worker process itself dying —
  is retried by Oban (`max_attempts: 5`, Oban's default backoff) rather
  than silently dropped.
- `WebhookControllerTest` no longer needs `async: false` or a
  `Process.sleep/1` to "give the Task a moment to land" — ticket
  creation happens in the same process, same sandboxed connection, as
  the test's own request. Asserting the job was enqueued
  (`assert_enqueued/1`) replaced asserting the ticket had already been
  processed by the time the response came back, which was never
  actually guaranteed even with the `Task` — just usually fast enough
  in practice.
- `SupportDesk.TaskSupervisor` and the Task-spawning code it existed
  for are gone; nothing else in this app used it.
