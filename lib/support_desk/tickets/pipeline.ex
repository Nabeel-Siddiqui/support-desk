defmodule SupportDesk.Tickets.Pipeline do
  @moduledoc """
  Runs a ticket through analyze -> match -> triage and commits the results.

  Design notes, since this is the part of the app most likely to bite
  someone in production:

    * The AI call and the CRM/user lookups happen *before* any database
      transaction opens. Never hold a DB connection checked out from the
      pool across a slow network call — that's how one flaky external API
      takes down unrelated requests fighting over the same pool.
    * The three results (analysis, matching, triage) are written in a
      single `Ecto.Multi` transaction, so a ticket never ends up
      half-analyzed if something goes wrong mid-write — either all three
      land, or none do and the ticket stays exactly where it was.
    * `mark_processing/1` is a deliberate exception to that: it's its own
      immediate, uncommitted-with-anything-else write, so the ticket
      dashboard shows "processing" while the (possibly multi-second) AI
      call is in flight, instead of looking untouched.
    * `process/1` itself is called from `ProcessTicketWorker` (Oban), not
      run inline on the webhook's own request — see
      [ADR 4](../../../docs/decisions/0004-oban-replaces-the-fire-and-forget-task.md).
      If the worker process dies mid-pipeline (OOM, node restart) after
      `mark_processing/1` but before the final commit, Oban retries the
      job rather than leaving the ticket stuck showing :processing
      forever — re-running `mark_processing/1` on a ticket already
      `:processing` is a harmless no-op update.
  """

  require Logger

  alias Ecto.Multi
  alias SupportDesk.Repo
  alias SupportDesk.Tickets.{AI, Matcher, ProcessTicketWorker, Ticket, Triage}

  @doc """
  Runs a ticket through analyze -> match -> triage, committing all three
  results atomically. If any step raises, the ticket is marked :failed
  instead of crashing the caller.
  """
  @spec process(Ticket.t()) :: {:ok, Ticket.t()} | {:error, Ecto.Changeset.t()}
  def process(%Ticket{} = ticket) do
    with {:ok, ticket} <- mark_processing(ticket) do
      run_pipeline(ticket)
    end
  rescue
    exception ->
      Logger.error("ticket pipeline crashed",
        ticket_id: ticket.id,
        exception: Exception.format(:error, exception, __STACKTRACE__)
      )

      mark_failed(ticket)
  end

  @doc """
  Creates a ticket from a webhook payload and enqueues it for processing
  — the ticket row and its `ProcessTicketWorker` job are written in one
  transaction, so a job can never be missing for a ticket that exists
  (or vice versa). A duplicate `external_id` (the webhook redelivering
  the same message) is treated as success rather than an error, since
  the caller (an at-least-once webhook sender) shouldn't be punished
  for retrying a delivery we already handled.
  """
  @spec receive(map()) :: {:ok, Ticket.t() | :duplicate} | {:error, Ecto.Changeset.t()}
  def receive(attrs) do
    changeset = Ticket.intake_changeset(%Ticket{}, attrs)

    Multi.new()
    |> Multi.insert(:ticket, changeset)
    |> Oban.insert(:process_job, fn %{ticket: ticket} ->
      ProcessTicketWorker.new(%{ticket_id: ticket.id})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{ticket: ticket}} ->
        {:ok, ticket}

      {:error, :ticket, changeset, _changes_so_far} ->
        if duplicate_external_id?(changeset) do
          {:ok, :duplicate}
        else
          {:error, changeset}
        end
    end
  end

  defp duplicate_external_id?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:external_id, {_msg, opts}} -> Keyword.get(opts, :constraint) == :unique
      _ -> false
    end)
  end

  defp mark_processing(ticket) do
    ticket
    |> Ticket.triage_changeset(%{status: :processing})
    |> Repo.update()
  end

  defp run_pipeline(ticket) do
    analysis = AI.analyze(ticket)
    matching = Matcher.match(ticket.from_email)
    decision = Triage.decide(triage_input(analysis, matching))

    multi =
      Multi.new()
      |> Multi.update(:analysis, Ticket.analysis_changeset(ticket, analysis))
      |> Multi.update(:matching, fn %{analysis: t} -> Ticket.matching_changeset(t, matching) end)
      |> Multi.update(:triage, fn %{matching: t} ->
        Ticket.triage_changeset(t, triage_attrs(decision))
      end)

    case Repo.transaction(multi) do
      {:ok, %{triage: ticket}} ->
        perform_side_effect(ticket, decision)
        {:ok, ticket}

      {:error, _failed_step, changeset, _changes_so_far} ->
        {:error, changeset}
    end
  end

  defp triage_input(analysis, matching) do
    %{
      intent: analysis.intent,
      sentiment: analysis.sentiment,
      urgency: analysis.urgency,
      ai_confidence: analysis.ai_confidence,
      known_customer: matching.known_customer,
      crm_account: matching.crm_account
    }
  end

  defp triage_attrs(decision) do
    %{
      status: decision.status,
      queue: decision.queue,
      priority: decision.priority,
      routing_reason: decision.reason
    }
  end

  # Side effects live here for now. In a bigger app these would enqueue a
  # Slack notification, send an auto-reply email, or push into a routing
  # queue — kept as log lines to keep this project dependency-free.
  defp perform_side_effect(ticket, %{status: :escalated}) do
    Logger.info("ticket escalated",
      ticket_id: ticket.id,
      queue: ticket.queue,
      priority: ticket.priority,
      reason: ticket.routing_reason
    )
  end

  defp perform_side_effect(ticket, %{status: :auto_resolved}) do
    Logger.info("ticket auto-resolved",
      ticket_id: ticket.id,
      queue: ticket.queue,
      reason: ticket.routing_reason
    )
  end

  defp perform_side_effect(ticket, %{status: :routed}) do
    Logger.info("ticket routed",
      ticket_id: ticket.id,
      queue: ticket.queue,
      priority: ticket.priority,
      reason: ticket.routing_reason
    )
  end

  defp perform_side_effect(_ticket, _decision), do: :ok

  defp mark_failed(ticket) do
    ticket
    |> Ticket.failed_changeset()
    |> Repo.update()
  end
end
