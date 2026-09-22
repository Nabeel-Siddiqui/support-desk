defmodule SupportDesk.Tickets do
  @moduledoc """
  Public context for ticket CRUD and queries. Business-process
  orchestration (the analyze -> match -> triage pipeline) lives in
  `SupportDesk.Tickets.Pipeline` — kept separate so this module stays a
  straightforward admin-CRUD surface instead of accumulating both
  responsibilities.
  """

  import Ecto.Query

  alias SupportDesk.Repo
  alias SupportDesk.Tickets.{Pipeline, Ticket}

  @doc "Saves the raw intake fields as a new ticket, status :new, without processing it."
  @spec create(map()) :: {:ok, Ticket.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %Ticket{}
    |> Ticket.intake_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Lists tickets, most recent first."
  @spec list_tickets() :: [Ticket.t()]
  def list_tickets, do: Repo.all(from t in Ticket, order_by: [desc: t.inserted_at])

  @doc """
  Lists tickets matching the given filters, most recent first, with
  pagination.

  Options:
    * `:status` - restrict to a single status atom, or `nil` for all
    * `:search` - case-insensitive match against subject, from_name, or from_email
    * `:page` - 1-indexed page number (default 1)
    * `:page_size` - rows per page (default 25)

  Returns `%{tickets: [...], page: integer, page_size: integer, total_count: integer, total_pages: integer}`.
  """
  @spec list_tickets(map()) :: %{
          tickets: [Ticket.t()],
          page: pos_integer(),
          page_size: pos_integer(),
          total_count: non_neg_integer(),
          total_pages: non_neg_integer()
        }
  def list_tickets(opts) when is_map(opts) do
    page = max(Map.get(opts, :page, 1), 1)
    page_size = Map.get(opts, :page_size, 25)

    base_query =
      Ticket
      |> filter_by_status(Map.get(opts, :status))
      |> filter_by_search(Map.get(opts, :search))

    total_count = Repo.aggregate(base_query, :count, :id)
    total_pages = max(ceil(total_count / page_size), 1)

    tickets =
      base_query
      |> order_by([t], desc: t.inserted_at)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> Repo.all()

    %{
      tickets: tickets,
      page: page,
      page_size: page_size,
      total_count: total_count,
      total_pages: total_pages
    }
  end

  defp filter_by_status(query, nil), do: query
  defp filter_by_status(query, status), do: where(query, [t], t.status == ^status)

  defp filter_by_search(query, search) when is_binary(search) and search != "" do
    pattern = "%#{search}%"

    where(
      query,
      [t],
      ilike(t.subject, ^pattern) or ilike(t.from_name, ^pattern) or ilike(t.from_email, ^pattern)
    )
  end

  defp filter_by_search(query, _search), do: query

  @doc "Gets a single ticket by id, raising if it doesn't exist."
  @spec get_ticket!(term()) :: Ticket.t()
  def get_ticket!(id), do: Repo.get!(Ticket, id)

  @doc "Ticket counts grouped by status, for the home dashboard."
  @spec ticket_counts() :: %{atom() => non_neg_integer()}
  def ticket_counts do
    Ticket
    |> group_by([t], t.status)
    |> select([t], {t.status, count(t.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "An empty/prefilled changeset for the 'new ticket' form."
  @spec change_new_ticket(Ticket.t(), map()) :: Ecto.Changeset.t()
  def change_new_ticket(%Ticket{} = ticket \\ %Ticket{}, attrs \\ %{}) do
    Ticket.intake_changeset(ticket, attrs)
  end

  @doc "A changeset for the 'edit ticket' form (intake + triage fields)."
  @spec change_edit_ticket(Ticket.t(), map()) :: Ecto.Changeset.t()
  def change_edit_ticket(%Ticket{} = ticket, attrs \\ %{}) do
    Ticket.edit_changeset(ticket, attrs)
  end

  @doc """
  Manually adds a ticket (e.g. from the UI, rather than a webhook) and runs
  it through the same analyze -> match -> triage pipeline.
  """
  @spec add_ticket(map()) :: {:ok, Ticket.t()} | {:error, Ecto.Changeset.t()}
  def add_ticket(attrs) do
    with {:ok, ticket} <- create(attrs) do
      Pipeline.process(ticket)
    end
  end

  @doc """
  Creates a ticket from a webhook payload and runs it through the pipeline.
  See `SupportDesk.Tickets.Pipeline.receive/1`.
  """
  @spec receive(map()) :: {:ok, Ticket.t() | :duplicate} | {:error, Ecto.Changeset.t()}
  defdelegate receive(attrs), to: Pipeline

  @doc "Re-runs the pipeline on an already-created ticket."
  @spec process(Ticket.t()) :: {:ok, Ticket.t()} | {:error, Ecto.Changeset.t()}
  defdelegate process(ticket), to: Pipeline

  @doc "Updates a ticket's intake and/or triage fields directly."
  @spec update_ticket(Ticket.t(), map()) :: {:ok, Ticket.t()} | {:error, Ecto.Changeset.t()}
  def update_ticket(%Ticket{} = ticket, attrs) do
    ticket
    |> Ticket.edit_changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a ticket."
  @spec delete_ticket(Ticket.t()) :: {:ok, Ticket.t()} | {:error, Ecto.Changeset.t()}
  def delete_ticket(%Ticket{} = ticket), do: Repo.delete(ticket)

  @doc "Marks a ticket as resolved by a human."
  @spec resolve_ticket(Ticket.t()) :: {:ok, Ticket.t()} | {:error, Ecto.Changeset.t()}
  def resolve_ticket(%Ticket{} = ticket) do
    ticket
    |> Ticket.triage_changeset(%{status: :resolved, routing_reason: "Manually resolved"})
    |> Repo.update()
  end

  @doc "Reopens a resolved/closed ticket, sending it back to :new."
  @spec reopen_ticket(Ticket.t()) :: {:ok, Ticket.t()} | {:error, Ecto.Changeset.t()}
  def reopen_ticket(%Ticket{} = ticket) do
    ticket
    |> Ticket.triage_changeset(%{status: :new, routing_reason: "Reopened"})
    |> Repo.update()
  end
end
