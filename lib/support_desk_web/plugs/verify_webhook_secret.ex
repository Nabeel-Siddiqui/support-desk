defmodule SupportDeskWeb.Plugs.VerifyWebhookSecret do
  @moduledoc """
  Rejects inbound webhook requests that don't present the shared secret
  configured at `:support_desk, :webhook_secret`, via the `x-webhook-secret`
  header. Uses a constant-time comparison to avoid timing side-channels.
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    expected = Application.fetch_env!(:support_desk, :webhook_secret)
    provided = conn |> get_req_header("x-webhook-secret") |> List.first()

    if is_binary(provided) and byte_size(provided) > 0 and
         Plug.Crypto.secure_compare(provided, expected) do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(401, Jason.encode!(%{error: "missing or invalid x-webhook-secret header"}))
      |> halt()
    end
  end
end
