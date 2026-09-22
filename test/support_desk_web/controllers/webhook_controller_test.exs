defmodule SupportDeskWeb.WebhookControllerTest do
  # async: false — the webhook handler processes the ticket in a spawned
  # Task, which needs the Ecto sandbox connection shared across processes
  # rather than pinned to the test process (see ConnCase/DataCase docs on
  # testing code that spawns its own processes).
  use SupportDeskWeb.ConnCase, async: false

  alias SupportDesk.Tickets

  # The webhook endpoint is a separate trust boundary from the admin UI —
  # it authenticates via a shared secret header, not the browser's basic
  # auth, so these requests deliberately strip the ConnCase-provided
  # Authorization header and use their own.
  defp webhook_conn(conn) do
    Plug.Conn.delete_req_header(conn, "authorization")
  end

  defp with_secret(conn, secret \\ "test-webhook-secret") do
    Plug.Conn.put_req_header(conn, "x-webhook-secret", secret)
  end

  describe "POST /webhooks/inbound" do
    test "rejects requests with no secret header", %{conn: conn} do
      conn = conn |> webhook_conn() |> post(~p"/webhooks/inbound", %{})
      assert conn.status == 401
    end

    test "rejects requests with the wrong secret", %{conn: conn} do
      conn =
        conn
        |> webhook_conn()
        |> with_secret("wrong-secret")
        |> post(~p"/webhooks/inbound", %{})

      assert conn.status == 401
    end

    test "rejects a payload with no parseable sender as 422", %{conn: conn} do
      conn =
        conn
        |> webhook_conn()
        |> with_secret()
        |> post(~p"/webhooks/inbound", %{"subject" => "Hello", "text" => "body"})

      assert conn.status == 422
      assert %{"errors" => %{"from_email" => _}} = json_response(conn, 422)
    end

    test "accepts a well-formed payload, returns instantly, and processes it", %{conn: conn} do
      conn =
        conn
        |> webhook_conn()
        |> with_secret()
        |> post(~p"/webhooks/inbound", %{
          "from" => "Jane Doe <jane@example.com>",
          "subject" => "How do I reset my password?",
          "text" => "How do I reset my password?",
          "message_id" => "webhook-msg-1"
        })

      assert conn.status == 200
      assert conn.resp_body == ""

      # the Task is fire-and-forget; give it a moment to land
      Process.sleep(50)

      ticket = Enum.find(Tickets.list_tickets(), &(&1.external_id == "webhook-msg-1"))
      assert ticket
      assert ticket.from_email == "jane@example.com"
      assert ticket.from_name == "Jane Doe"
      assert ticket.status != :new
    end
  end
end
