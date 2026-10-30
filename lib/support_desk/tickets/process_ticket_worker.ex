defmodule SupportDesk.Tickets.ProcessTicketWorker do
  @moduledoc """
  Runs `Pipeline.process/1` for one ticket, via Oban, instead of a
  fire-and-forget `Task`. A crash in anything before `process/1`'s own
  `rescue` can catch it (the DB write that creates the job in the first
  place, or this worker process itself dying) is retried by Oban rather
  than silently dropped. See
  [ADR 4](../../../docs/decisions/0004-oban-replaces-the-fire-and-forget-task.md).
  """

  use Oban.Worker, queue: :tickets, max_attempts: 5

  alias SupportDesk.Tickets

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ticket_id" => ticket_id}}) do
    ticket = Tickets.get_ticket!(ticket_id)

    case Tickets.process(ticket) do
      {:ok, _ticket} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end
end
