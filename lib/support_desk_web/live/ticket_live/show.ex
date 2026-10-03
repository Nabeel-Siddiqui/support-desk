defmodule SupportDeskWeb.TicketLive.Show do
  use SupportDeskWeb, :live_view

  alias SupportDesk.Tickets
  alias SupportDesk.Tickets.Ticket

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:ticket, Tickets.get_ticket!(id))}
  end

  defp page_title(:show), do: "Show Ticket"
  defp page_title(:edit), do: "Edit Ticket"

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Ticket #{@ticket.id}
      <:subtitle>{@ticket.subject}</:subtitle>
      <:actions>
        <.link patch={~p"/tickets/#{@ticket}/show/edit"}>
          <.button>Edit</.button>
        </.link>
        <.button :if={Ticket.resolvable?(@ticket)} phx-click="resolve">Resolve</.button>
        <.button :if={@ticket.status == :resolved} phx-click="reopen">Reopen</.button>
        <.button
          phx-click="delete"
          data-confirm="Delete this ticket? This cannot be undone."
          class="bg-red-600 hover:bg-red-500"
        >
          Delete
        </.button>
        <.back navigate={~p"/tickets"}>Back to tickets</.back>
      </:actions>
    </.header>

    <.list>
      <:item title="Channel">{@ticket.channel}</:item>
      <:item title="External ID">{@ticket.external_id || "—"}</:item>
      <:item title="From">{@ticket.from_name} &lt;{@ticket.from_email}&gt;</:item>
      <:item title="Subject">{@ticket.subject}</:item>
      <:item title="Body"><pre class="whitespace-pre-wrap font-sans">{@ticket.body}</pre></:item>
    </.list>

    <.header class="mt-10">AI analysis</.header>
    <.list>
      <:item title="Intent">{@ticket.intent || "—"}</:item>
      <:item title="Sentiment">{@ticket.sentiment || "—"}</:item>
      <:item title="Urgency">{@ticket.urgency || "—"}</:item>
      <:item title="Summary">{@ticket.summary || "—"}</:item>
      <:item title="Confidence">{@ticket.ai_confidence || "—"}</:item>
    </.list>

    <.header class="mt-10">Matching</.header>
    <.list>
      <:item title="Matched user ID">{@ticket.matched_user_id || "—"}</:item>
      <:item title="Known customer">{@ticket.known_customer}</:item>
      <:item title="CRM account">
        <pre class="whitespace-pre-wrap font-sans">{inspect(@ticket.crm_account)}</pre>
      </:item>
    </.list>

    <.header class="mt-10">Triage</.header>
    <.list>
      <:item title="Status">{@ticket.status}</:item>
      <:item title="Queue">{@ticket.queue || "—"}</:item>
      <:item title="Priority">{@ticket.priority || "—"}</:item>
      <:item title="Reason">{@ticket.routing_reason || "—"}</:item>
    </.list>

    <.modal
      :if={@live_action == :edit}
      id="ticket-modal"
      show
      on_cancel={JS.patch(~p"/tickets/#{@ticket}")}
    >
      <.live_component
        module={SupportDeskWeb.TicketLive.FormComponent}
        id={@ticket.id}
        title={@page_title}
        action={@live_action}
        ticket={@ticket}
        patch={~p"/tickets/#{@ticket}"}
      />
    </.modal>
    """
  end

  @impl true
  def handle_info({SupportDeskWeb.TicketLive.FormComponent, {:saved, ticket}}, socket) do
    {:noreply, assign(socket, :ticket, ticket)}
  end

  @impl true
  def handle_event("resolve", _params, socket) do
    {:ok, ticket} = Tickets.resolve_ticket(socket.assigns.ticket)
    {:noreply, assign(socket, :ticket, ticket)}
  end

  def handle_event("reopen", _params, socket) do
    {:ok, ticket} = Tickets.reopen_ticket(socket.assigns.ticket)
    {:noreply, assign(socket, :ticket, ticket)}
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Tickets.delete_ticket(socket.assigns.ticket)

    {:noreply,
     socket
     |> put_flash(:info, "Ticket deleted")
     |> push_navigate(to: ~p"/tickets")}
  end
end
