defmodule SupportDeskWeb.HomeLive do
  use SupportDeskWeb, :live_view

  alias SupportDesk.Tickets

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :counts, Tickets.ticket_counts())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Support Desk
      <:subtitle>
        A webhook comes in, gets saved as a ticket, and runs through
        analyze &rarr; match &rarr; triage automatically.
      </:subtitle>
      <:actions>
        <.link navigate={~p"/tickets/new"}>
          <.button>New ticket</.button>
        </.link>
        <.link navigate={~p"/tickets"}>
          <.button>View all tickets</.button>
        </.link>
      </:actions>
    </.header>

    <div class="mt-10 grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-6">
      <.stat_card label="Total" value={total(@counts)} />
      <.stat_card label="New" value={count(@counts, :new)} />
      <.stat_card label="Processing" value={count(@counts, :processing)} />
      <.stat_card label="Routed" value={count(@counts, :routed)} />
      <.stat_card label="Escalated" value={count(@counts, :escalated)} highlight="red" />
      <.stat_card label="Resolved" value={resolved(@counts)} highlight="green" />
    </div>
    """
  end

  defp total(counts), do: counts |> Map.values() |> Enum.sum()
  defp count(counts, status), do: Map.get(counts, status, 0)
  defp resolved(counts), do: count(counts, :resolved) + count(counts, :auto_resolved)

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :highlight, :string, default: nil

  defp stat_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 p-4">
      <div class={[
        "text-3xl font-bold",
        @highlight == "red" && "text-red-700",
        @highlight == "green" && "text-green-700",
        is_nil(@highlight) && "text-zinc-900"
      ]}>
        {@value}
      </div>
      <div class="text-sm text-zinc-500">{@label}</div>
    </div>
    """
  end
end
