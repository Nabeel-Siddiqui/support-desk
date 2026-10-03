defmodule SupportDeskWeb.TicketLive.FormComponent do
  use SupportDeskWeb, :live_component

  alias SupportDesk.Tickets
  alias SupportDesk.Tickets.Ticket

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>
          <%= if @action == :new do %>
            Manually add a ticket. It runs through the same analyze/match/triage
            pipeline as a webhook delivery.
          <% else %>
            Edit the ticket's intake details, or manually override its triage.
          <% end %>
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="ticket-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:channel]} type="text" label="Channel" />
        <.input field={@form[:external_id]} type="text" label="External ID (optional)" />
        <.input field={@form[:from_name]} type="text" label="From name" />
        <.input field={@form[:from_email]} type="text" label="From email" />
        <.input field={@form[:subject]} type="text" label="Subject" />
        <.input field={@form[:body]} type="textarea" label="Body" />

        <div :if={@action == :edit} class="mt-6 border-t border-zinc-100 pt-6">
          <h3 class="text-sm font-semibold text-zinc-800">Triage overrides</h3>
          <.input field={@form[:status]} type="select" label="Status" options={status_options()} />
          <.input field={@form[:queue]} type="text" label="Queue" />
          <.input field={@form[:priority]} type="text" label="Priority" />
          <.input field={@form[:routing_reason]} type="text" label="Routing reason" />
        </div>

        <:actions>
          <.button phx-disable-with="Saving...">Save ticket</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{ticket: ticket, action: action} = assigns, socket) do
    changeset =
      case action do
        :new -> Tickets.change_new_ticket(ticket)
        :edit -> Tickets.change_edit_ticket(ticket)
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn -> to_form(changeset) end)}
  end

  @impl true
  def handle_event("validate", %{"ticket" => ticket_params}, socket) do
    changeset =
      case socket.assigns.action do
        :new -> Tickets.change_new_ticket(socket.assigns.ticket, ticket_params)
        :edit -> Tickets.change_edit_ticket(socket.assigns.ticket, ticket_params)
      end

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"ticket" => ticket_params}, socket) do
    save_ticket(socket, socket.assigns.action, ticket_params)
  end

  defp save_ticket(socket, :edit, ticket_params) do
    case Tickets.update_ticket(socket.assigns.ticket, ticket_params) do
      {:ok, ticket} ->
        notify_parent({:saved, ticket})

        {:noreply,
         socket
         |> put_flash(:info, "Ticket updated")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_ticket(socket, :new, ticket_params) do
    case Tickets.add_ticket(ticket_params) do
      {:ok, ticket} ->
        notify_parent({:saved, ticket})

        {:noreply,
         socket
         |> put_flash(:info, "Ticket created")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp status_options, do: Ticket.status_options()
end
