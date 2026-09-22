defmodule SupportDeskWeb.TicketLive.Index do
  use SupportDeskWeb, :live_view

  alias SupportDesk.Tickets
  alias SupportDesk.Tickets.Ticket

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :tickets, Tickets.list_tickets())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
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

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Tickets")
    |> assign(:ticket, nil)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Tickets
      <:subtitle>Read-write view of the support ticket pipeline.</:subtitle>
      <:actions>
        <.link patch={~p"/tickets/new"}>
          <.button>New ticket</.button>
        </.link>
      </:actions>
    </.header>

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

    <.modal :if={@live_action in [:new, :edit]} id="ticket-modal" show on_cancel={JS.patch(~p"/tickets")}>
      <.live_component
        module={SupportDeskWeb.TicketLive.FormComponent}
        id={@ticket.id || :new}
        title={@page_title}
        action={@live_action}
        ticket={@ticket}
        patch={~p"/tickets"}
      />
    </.modal>
    """
  end

  @impl true
  def handle_info({SupportDeskWeb.TicketLive.FormComponent, {:saved, ticket}}, socket) do
    {:noreply, stream_insert(socket, :tickets, ticket, at: 0)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    ticket = Tickets.get_ticket!(id)
    {:ok, _} = Tickets.delete_ticket(ticket)

    {:noreply, stream_delete(socket, :tickets, ticket)}
  end

  def handle_event("resolve", %{"id" => id}, socket) do
    ticket = Tickets.get_ticket!(id)
    {:ok, ticket} = Tickets.resolve_ticket(ticket)
    {:noreply, stream_insert(socket, :tickets, ticket)}
  end

  def handle_event("reopen", %{"id" => id}, socket) do
    ticket = Tickets.get_ticket!(id)
    {:ok, ticket} = Tickets.reopen_ticket(ticket)
    {:noreply, stream_insert(socket, :tickets, ticket)}
  end

  defp resolvable?(t), do: t.status not in [:resolved, :failed]

  defp status_badge_class(status) when status in [:escalated, :failed],
    do: "text-red-700 font-semibold"

  defp status_badge_class(status) when status in [:auto_resolved, :resolved],
    do: "text-green-700"

  defp status_badge_class(:routed), do: "text-blue-700"
  defp status_badge_class(_), do: "text-zinc-500"
end
