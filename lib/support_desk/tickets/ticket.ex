defmodule SupportDesk.Tickets.Ticket do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(new processing auto_resolved routed escalated resolved failed)a
  @email_regex ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

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

  @type t :: %__MODULE__{
          channel: String.t() | nil,
          external_id: String.t() | nil,
          from_email: String.t() | nil,
          from_name: String.t() | nil,
          subject: String.t() | nil,
          body: String.t() | nil,
          intent: String.t() | nil,
          sentiment: String.t() | nil,
          urgency: String.t() | nil,
          summary: String.t() | nil,
          ai_confidence: float() | nil,
          matched_user_id: integer() | nil,
          crm_account: map() | nil,
          known_customer: boolean(),
          status: atom(),
          queue: String.t() | nil,
          priority: String.t() | nil,
          routing_reason: String.t() | nil
        }

  @intake_fields ~w(channel external_id from_email from_name subject body)a
  @ai_fields ~w(intent sentiment urgency summary ai_confidence)a
  @matching_fields ~w(matched_user_id crm_account known_customer)a
  @triage_fields ~w(status queue priority routing_reason)a

  @doc "Validates and casts the fields a new ticket arrives with (webhook or manual entry)."
  @spec intake_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def intake_changeset(ticket, attrs) do
    ticket
    |> cast(attrs, @intake_fields)
    |> validate_required([:channel, :from_email])
    |> validate_format(:from_email, @email_regex, message: "must be a valid email address")
    |> unique_constraint(:external_id)
  end

  @doc "Full manual edit: intake fields plus the human-editable triage fields."
  @spec edit_changeset(t(), map()) :: Ecto.Changeset.t()
  def edit_changeset(ticket, attrs) do
    ticket
    |> cast(attrs, @intake_fields ++ @triage_fields)
    |> validate_required([:channel, :from_email])
    |> validate_format(:from_email, @email_regex, message: "must be a valid email address")
    |> unique_constraint(:external_id)
  end

  @spec analysis_changeset(t(), map()) :: Ecto.Changeset.t()
  def analysis_changeset(ticket, attrs), do: cast(ticket, attrs, @ai_fields)

  @spec matching_changeset(t(), map()) :: Ecto.Changeset.t()
  def matching_changeset(ticket, attrs), do: cast(ticket, attrs, @matching_fields)

  @spec triage_changeset(t(), map()) :: Ecto.Changeset.t()
  def triage_changeset(ticket, attrs), do: cast(ticket, attrs, @triage_fields)

  @spec failed_changeset(t()) :: Ecto.Changeset.t()
  def failed_changeset(ticket), do: change(ticket, status: :failed)
end
