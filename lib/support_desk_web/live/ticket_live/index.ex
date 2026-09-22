defmodule SupportDeskWeb.TicketLive.Index do
  use SupportDeskWeb, :live_view

  alias SupportDesk.Tickets

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :tickets, Tickets.list_tickets())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Tickets
      <:subtitle>Read-only view of the support ticket pipeline.</:subtitle>
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
    </.table>
    """
  end

  defp status_badge_class(:escalated), do: "text-red-700 font-semibold"
  defp status_badge_class(:failed), do: "text-red-700 font-semibold"
  defp status_badge_class(:auto_resolved), do: "text-green-700"
  defp status_badge_class(:routed), do: "text-blue-700"
  defp status_badge_class(_), do: "text-zinc-500"
end
