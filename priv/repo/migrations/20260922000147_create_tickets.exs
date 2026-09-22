defmodule SupportDesk.Repo.Migrations.CreateTickets do
  use Ecto.Migration

  def change do
    create table(:tickets) do
      # Intake
      add :channel, :string, null: false
      add :external_id, :string
      add :from_email, :string, null: false
      add :from_name, :string
      add :subject, :string
      add :body, :text

      # AI analysis
      add :intent, :string
      add :sentiment, :string
      add :urgency, :string
      add :summary, :string
      add :ai_confidence, :float

      # Matching
      add :matched_user_id, :integer
      add :crm_account, :map
      add :known_customer, :boolean, null: false, default: false

      # Triage
      add :status, :string, null: false, default: "new"
      add :queue, :string
      add :priority, :string
      add :routing_reason, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tickets, [:external_id])
    create index(:tickets, [:status])
    create index(:tickets, [:from_email])
  end
end
