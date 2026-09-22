defmodule SupportDesk.Tickets do
  @moduledoc """
  Support ticket pipeline: a webhook payload comes in, gets saved as a
  ticket, then runs through analyze -> match -> triage, with results saved
  back onto the same row.
  """

  require Logger

  import Ecto.Query

  alias SupportDesk.Repo
  alias SupportDesk.Tickets.{AI, Matcher, Triage, Ticket}

  @doc "Saves the raw intake fields as a new ticket, status :new."
  def create(attrs) do
    %Ticket{}
    |> Ticket.intake_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Lists tickets, most recent first, for the ticket dashboard."
  def list_tickets do
    Repo.all(from t in Ticket, order_by: [desc: t.inserted_at])
  end

  @doc "Gets a single ticket by id, raising if it doesn't exist."
  def get_ticket!(id), do: Repo.get!(Ticket, id)

  @doc """
  Runs a ticket through analyze -> match -> triage, saving results back
  onto the row after each step. If any step raises, the ticket is marked
  :failed instead of crashing the caller.
  """
  def process(%Ticket{} = ticket) do
    with {:ok, ticket} <- mark_processing(ticket),
         {:ok, ticket} <- run_analysis(ticket),
         {:ok, ticket} <- run_matching(ticket),
         {:ok, ticket} <- run_triage(ticket) do
      {:ok, ticket}
    end
  rescue
    exception ->
      Logger.error(
        "SupportDesk.Tickets.process/1 failed for ticket #{ticket.id}: " <>
          Exception.format(:error, exception, __STACKTRACE__)
      )

      mark_failed(ticket)
  end

  @doc """
  Creates a ticket from a webhook payload and immediately processes it.
  A duplicate `external_id` (the webhook redelivering the same message) is
  treated as success rather than an error.
  """
  def receive(attrs) do
    case create(attrs) do
      {:ok, ticket} ->
        process(ticket)

      {:error, changeset} ->
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

  defp run_analysis(ticket) do
    result = AI.analyze(ticket)

    ticket
    |> Ticket.analysis_changeset(result)
    |> Repo.update()
  end

  defp run_matching(ticket) do
    result = Matcher.match(ticket.from_email)

    ticket
    |> Ticket.matching_changeset(result)
    |> Repo.update()
  end

  defp run_triage(ticket) do
    decision = Triage.decide(ticket)

    attrs = %{
      status: decision.status,
      queue: decision.queue,
      priority: decision.priority,
      routing_reason: decision.reason
    }

    with {:ok, ticket} <- ticket |> Ticket.triage_changeset(attrs) |> Repo.update() do
      perform_side_effect(ticket, decision)
      {:ok, ticket}
    end
  end

  # Side effects live here for now. In a bigger app these would enqueue a
  # Slack notification, send an auto-reply email, or push into a routing
  # queue — kept as log lines to keep this project dependency-free.
  defp perform_side_effect(ticket, %{status: :escalated}) do
    Logger.info(
      "[escalate] ticket=#{ticket.id} queue=#{ticket.queue} priority=#{ticket.priority} reason=#{ticket.routing_reason}"
    )
  end

  defp perform_side_effect(ticket, %{status: :auto_resolved}) do
    Logger.info(
      "[auto_resolve] ticket=#{ticket.id} queue=#{ticket.queue} reason=#{ticket.routing_reason}"
    )
  end

  defp perform_side_effect(ticket, %{status: :routed}) do
    Logger.info(
      "[route] ticket=#{ticket.id} queue=#{ticket.queue} priority=#{ticket.priority} reason=#{ticket.routing_reason}"
    )
  end

  defp perform_side_effect(_ticket, _decision), do: :ok

  defp mark_failed(ticket) do
    ticket
    |> Ticket.failed_changeset()
    |> Repo.update()
  end
end
