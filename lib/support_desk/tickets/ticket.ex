defmodule SupportDesk.Tickets.Ticket do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(new processing auto_resolved routed escalated resolved failed)a

  schema "tickets" do
    # Intake
    field :channel, :string
    field :external_id, :string
    field :from_email, :string
    field :from_name, :string
    field :subject, :string
    field :body, :string

    # AI analysis
    field :intent, :string
    field :sentiment, :string
    field :urgency, :string
    field :summary, :string
    field :ai_confidence, :float

    # Matching
    field :matched_user_id, :integer
    field :crm_account, :map
    field :known_customer, :boolean, default: false

    # Triage
    field :status, Ecto.Enum, values: @statuses, default: :new
    field :queue, :string
    field :priority, :string
    field :routing_reason, :string

    timestamps(type: :utc_datetime_usec)
  end

  @intake_fields ~w(channel external_id from_email from_name subject body)a
  @ai_fields ~w(intent sentiment urgency summary ai_confidence)a
  @matching_fields ~w(matched_user_id crm_account known_customer)a
  @triage_fields ~w(status queue priority routing_reason)a

  def intake_changeset(ticket, attrs) do
    ticket
    |> cast(attrs, @intake_fields)
    |> validate_required([:channel, :from_email])
    |> unique_constraint(:external_id)
  end

  def analysis_changeset(ticket, attrs) do
    cast(ticket, attrs, @ai_fields)
  end

  def matching_changeset(ticket, attrs) do
    cast(ticket, attrs, @matching_fields)
  end

  def triage_changeset(ticket, attrs) do
    cast(ticket, attrs, @triage_fields)
  end

  def failed_changeset(ticket) do
    change(ticket, status: :failed)
  end

  @doc "Full manual edit: intake fields plus the human-editable triage fields."
  def edit_changeset(ticket, attrs) do
    ticket
    |> cast(attrs, @intake_fields ++ @triage_fields)
    |> validate_required([:channel, :from_email])
    |> unique_constraint(:external_id)
  end
end
