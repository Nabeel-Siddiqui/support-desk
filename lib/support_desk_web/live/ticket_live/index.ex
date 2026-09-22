defmodule SupportDeskWeb.TicketLive.Index do
  use SupportDeskWeb, :live_view

  alias SupportDesk.Tickets
  alias SupportDesk.Tickets.Ticket

  @page_size 20

  @impl true
  def mount(_params, _session, socket) do
    # Sane defaults so a direct link to /tickets/new or /tickets/:id/edit
    # (which carry no filter query params) doesn't crash the template
    # underneath the modal before an :index handle_params has ever run.
    {:ok,
     socket
     |> assign(:filters, %{status: nil, search: "", page: 1, page_size: @page_size})
     |> assign(:total_pages, 0)
     |> assign(:total_count, 0)
     |> stream(:tickets, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  # Filters/pagination only ever reload from the URL on :index — patching
  # to /tickets/new or /tickets/:id/edit must not reset whatever filter the
  # list underneath the modal currently has applied, since those routes
  # carry no query string of their own.
  defp apply_action(socket, :index, params) do
    filters = %{
      status: parse_status(params["status"]),
      search: Map.get(params, "search", ""),
      page: parse_page(params["page"]),
      page_size: @page_size
    }

    socket
    |> assign(:page_title, "Tickets")
    |> assign(:ticket, nil)
    |> load_tickets(filters)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Ticket")
    |> assign(:ticket, Tickets.get_ticket!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Ticket")
    |> assign(:ticket, %Ticket{})
  end

  # Re-runs the current filter/page query. Used after any mutation
  # (create/edit/resolve/reopen/delete) instead of patching the changed row
  # directly into the stream — a resolved ticket should simply disappear
  # from a `status=escalated` filtered view, not linger there with a
  # mismatched badge, and a patched-in row would do exactly that.
  defp load_tickets(socket, filters) do
    %{tickets: tickets, total_pages: total_pages, total_count: total_count} =
      Tickets.list_tickets(filters)

    socket
    |> assign(:filters, filters)
    |> assign(:total_pages, total_pages)
    |> assign(:total_count, total_count)
    |> stream(:tickets, tickets, reset: true)
  end

  defp parse_status(status) when status in [nil, ""], do: nil

  defp parse_status(status) do
    if status in Enum.map(Ecto.Enum.values(Ticket, :status), &to_string/1) do
      # Only ever converts to an atom that already exists (the enum values
      # are compiled into the schema) — never String.to_atom on raw user
      # input, that's an unbounded-atom-table DoS waiting to happen.
      String.to_existing_atom(status)
    end
  end

  defp parse_page(nil), do: 1

  defp parse_page(value) do
    case Integer.parse(value) do
      {n, _} when n > 0 -> n
      _ -> 1
    end
  end

  defp list_path(filters, overrides \\ %{}) do
    query =
      filters
      |> Map.merge(overrides)
      |> Map.take([:status, :search, :page])
      |> Enum.reject(fn {k, v} -> v in [nil, "", false] or (k == :page and v == 1) end)

    ~p"/tickets?#{query}"
  end

  defp status_options do
    [{"All statuses", ""} | Enum.map(Ecto.Enum.values(Ticket, :status), &{humanize(&1), &1})]
  end

  defp status_selected?(nil, ""), do: true
  defp status_selected?(_current, ""), do: false
  defp status_selected?(current, value), do: current == value

  defp humanize(atom), do: atom |> to_string() |> String.replace("_", " ") |> String.capitalize()

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Tickets
      <:subtitle>
        {@total_count} total &middot; showing page {@filters.page} of {@total_pages}
      </:subtitle>
      <:actions>
        <.link patch={~p"/tickets/new"}>
          <.button>New ticket</.button>
        </.link>
      </:actions>
    </.header>

    <form phx-change="filter" class="mt-6 flex flex-wrap items-end gap-4">
      <div>
        <label class="block text-sm font-semibold text-zinc-700" for="filter-status">Status</label>
        <select id="filter-status" name="status" class="mt-1 rounded-md border-zinc-300 text-sm">
          <option
            :for={{label, value} <- status_options()}
            value={value}
            selected={status_selected?(@filters.status, value)}
          >
            {label}
          </option>
        </select>
      </div>
      <div>
        <label class="block text-sm font-semibold text-zinc-700" for="filter-search">Search</label>
        <input
          type="text"
          id="filter-search"
          name="search"
          value={@filters.search}
          placeholder="Subject, name, or email"
          class="mt-1 rounded-md border-zinc-300 text-sm"
        />
      </div>
    </form>

    <.table
      id="tickets"
      rows={@streams.tickets}
      row_click={fn {_id, t} -> JS.navigate(~p"/tickets/#{t}") end}
    >
      <:col :let={{_id, t}} label="From">
        {t.from_name || t.from_email}
      </:col>
      <:col :let={{_id, t}} label="Subject">{t.subject}</:col>
      <:col :let={{_id, t}} label="Intent">{t.intent}</:col>
      <:col :let={{_id, t}} label="Sentiment">{t.sentiment}</:col>
      <:col :let={{_id, t}} label="Status">
        <span class={status_badge_class(t.status)}>{t.status}</span>
      </:col>
      <:col :let={{_id, t}} label="Queue">{t.queue}</:col>
      <:col :let={{_id, t}} label="Priority">{t.priority}</:col>
      <:col :let={{_id, t}} label="Received">
        {Calendar.strftime(t.inserted_at, "%Y-%m-%d %H:%M")}
      </:col>
      <:action :let={{_id, t}}>
        <.link patch={~p"/tickets/#{t}/edit"}>Edit</.link>
      </:action>
      <:action :let={{_id, t}}>
        <.link :if={resolvable?(t)} phx-click="resolve" phx-value-id={t.id}>
          Resolve
        </.link>
        <.link :if={t.status == :resolved} phx-click="reopen" phx-value-id={t.id}>
          Reopen
        </.link>
      </:action>
      <:action :let={{id, t}}>
        <.link
          phx-click={JS.push("delete", value: %{id: t.id}) |> hide("##{id}")}
          data-confirm="Delete this ticket?"
        >
          Delete
        </.link>
      </:action>
    </.table>

    <div class="mt-4 flex items-center justify-between text-sm text-zinc-600">
      <span>Page {@filters.page} of {@total_pages} ({@total_count} tickets)</span>
      <div class="flex gap-4">
        <.link :if={@filters.page > 1} patch={list_path(@filters, %{page: @filters.page - 1})}>
          &larr; Previous
        </.link>
        <.link
          :if={@filters.page < @total_pages}
          patch={list_path(@filters, %{page: @filters.page + 1})}
        >
          Next &rarr;
        </.link>
      </div>
    </div>

    <.modal
      :if={@live_action in [:new, :edit]}
      id="ticket-modal"
      show
      on_cancel={JS.patch(list_path(@filters))}
    >
      <.live_component
        module={SupportDeskWeb.TicketLive.FormComponent}
        id={@ticket.id || :new}
        title={@page_title}
        action={@live_action}
        ticket={@ticket}
        patch={list_path(@filters)}
      />
    </.modal>
    """
  end

  @impl true
  def handle_event("filter", params, socket) do
    # Changing a filter always resets to page 1 — otherwise you can land on
    # "page 3" of a filtered result set that only has one page.
    query = %{status: params["status"], search: params["search"], page: 1}
    {:noreply, push_patch(socket, to: list_path(socket.assigns.filters, query))}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    ticket = Tickets.get_ticket!(id)
    {:ok, _} = Tickets.delete_ticket(ticket)
    {:noreply, load_tickets(socket, socket.assigns.filters)}
  end

  def handle_event("resolve", %{"id" => id}, socket) do
    ticket = Tickets.get_ticket!(id)
    {:ok, _ticket} = Tickets.resolve_ticket(ticket)
    {:noreply, load_tickets(socket, socket.assigns.filters)}
  end

  def handle_event("reopen", %{"id" => id}, socket) do
    ticket = Tickets.get_ticket!(id)
    {:ok, _ticket} = Tickets.reopen_ticket(ticket)
    {:noreply, load_tickets(socket, socket.assigns.filters)}
  end

  @impl true
  def handle_info({SupportDeskWeb.TicketLive.FormComponent, {:saved, _ticket}}, socket) do
    {:noreply, load_tickets(socket, socket.assigns.filters)}
  end

  defp resolvable?(t), do: t.status not in [:resolved, :failed]

  defp status_badge_class(status) when status in [:escalated, :failed],
    do: "text-red-700 font-semibold"

  defp status_badge_class(status) when status in [:auto_resolved, :resolved],
    do: "text-green-700"

  defp status_badge_class(:routed), do: "text-blue-700"
  defp status_badge_class(_), do: "text-zinc-500"
end
