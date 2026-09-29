# SupportDesk

A small support-ticket pipeline: a webhook receives a message, saves it, runs
it through analyze -> match -> triage, and saves the results back onto the
same row. Read/write ticket dashboard included. See `lib/support_desk/tickets/pipeline.ex`
for the design notes on why the pipeline is structured the way it is
(transaction boundaries, why the AI call happens outside of them, the
failure mode when a worker dies mid-pipeline).

## Running it locally

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix with `mix phx.server` or inside IEx with `iex -S mix phx.server`
  * Visit [`localhost:4000`](http://localhost:4000) — dev credentials are `admin` / `admin`
    (see `config/dev.exs`)

The whole browser UI sits behind HTTP Basic Auth — this is an internal
tool, not a public app. There's no per-user accounts system; if you need
individual attribution later, swap it for `mix phx.gen.auth`.

## Configuration

| Env var | Required in | Purpose |
|---|---|---|
| `WEBHOOK_SECRET` | prod | Shared secret the inbound webhook must send as `x-webhook-secret`. Dev/test have hardcoded defaults (see `config/dev.exs` / `config/test.exs`). |
| `ADMIN_USERNAME` / `ADMIN_PASSWORD` | prod | Basic Auth credentials gating the ticket UI. |
| `AI_ENABLED` | optional | Set to `true`/`1` to call Claude for ticket analysis. Unset (default) runs the deterministic keyword fallback — no API key needed, works offline and in tests. |
| `ANTHROPIC_API_KEY` | if `AI_ENABLED` | Required once AI is turned on; boot fails fast if it's missing while `AI_ENABLED` is set. |

Two more things are wired via application config, not env vars, since
they're functions/data rather than secrets:

```elixir
# Optional: look up the sender against your own user table. Skipped
# entirely if unset (no compile-time dependency on your Accounts context).
config :support_desk, :user_lookup, &MyApp.Accounts.get_user_by_email/1

# Optional: CRM accounts by sender email domain.
config :support_desk, :crm_accounts, %{
  "acme.com" => %{name: "Acme Corp", tier: "enterprise", owner: "jane@yourcompany.com"}
}
```

## Testing

  * `mix test` runs everything: DB-free unit tests for the AI
    fallback/matcher/triage rules (`test/support_desk/tickets_pipeline_test.exs`),
    an `Ecto.Multi` atomicity test for the pipeline
    (`test/support_desk/tickets/pipeline_test.exs`), webhook auth/validation
    tests, and LiveView tests driving the actual ticket CRUD/resolve UI.
