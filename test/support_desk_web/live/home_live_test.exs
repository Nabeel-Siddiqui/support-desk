defmodule SupportDeskWeb.HomeLiveTest do
  use SupportDeskWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SupportDesk.Tickets

  test "shows ticket counts by status", %{conn: conn} do
    {:ok, ticket} =
      Tickets.create(%{channel: "email", from_email: "a@example.com", subject: "Hi"})

    {:ok, _} = Tickets.resolve_ticket(ticket)

    {:ok, _home_live, html} = live(conn, ~p"/")

    assert html =~ "Support Desk"
    assert html =~ "Total"
    assert html =~ "Resolved"
  end
end
