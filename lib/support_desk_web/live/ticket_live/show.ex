defmodule SupportDeskWeb.TicketLive.Show do
  use SupportDeskWeb, :live_view

  alias SupportDesk.Tickets

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    {:noreply, assign(socket, :ticket, Tickets.get_ticket!(id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Ticket #{@ticket.id}
      <:subtitle>{@ticket.subject}</:subtitle>
      <:actions>
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
    """
  end
end
