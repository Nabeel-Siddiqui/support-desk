defmodule SupportDesk.Repo do
  use Ecto.Repo,
    otp_app: :support_desk,
    adapter: Ecto.Adapters.Postgres
end
