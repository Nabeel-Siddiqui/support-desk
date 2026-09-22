defmodule SupportDeskWeb.TicketLiveTest do
  use SupportDeskWeb.ConnCase

  import Phoenix.LiveViewTest

  alias SupportDesk.Tickets

  defp ticket_fixture(attrs \\ %{}) do
    {:ok, ticket} =
      attrs
      |> Enum.into(%{
        channel: "email",
        from_email: "fixture@example.com",
        from_name: "Fixture Customer",
        subject: "Original subject",
        body: "Original body"
      })
      |> Tickets.create()

    ticket
  end

  defp valid_new_attrs do
    %{
      channel: "email",
      from_email: "new-customer@example.com",
      from_name: "New Customer",
      subject: "How do I reset my password?",
      body: "How do I reset my password?"
    }
  end

  describe "Index" do
    test "lists all tickets", %{conn: conn} do
      ticket = ticket_fixture(%{subject: "Printer is on fire"})

      {:ok, _index_live, html} = live(conn, ~p"/tickets")

      assert html =~ "Tickets"
      assert html =~ ticket.subject
    end

    test "adds a new ticket through the modal form and runs it through the pipeline", %{
      conn: conn
    } do
      {:ok, index_live, _html} = live(conn, ~p"/tickets")

      assert index_live |> element("a", "New ticket") |> render_click() =~ "New Ticket"
      assert_patch(index_live, ~p"/tickets/new")

      # blank required field surfaces a validation error
      assert index_live
             |> form("#ticket-form", ticket: %{channel: "email", from_email: ""})
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#ticket-form", ticket: valid_new_attrs())
             |> render_submit()

      assert_patch(index_live, ~p"/tickets")

      html = render(index_live)
      assert html =~ "Ticket created"
      assert html =~ "New Customer"

      # the pipeline actually ran: how_to/account_access intent should route or auto-resolve
      [ticket] =
        Tickets.list_tickets() |> Enum.filter(&(&1.from_email == "new-customer@example.com"))

      assert ticket.intent in ["how_to", "account_access"]
      assert ticket.status != :new
    end

    test "edits a ticket via the modal form", %{conn: conn} do
      ticket = ticket_fixture()
      {:ok, index_live, _html} = live(conn, ~p"/tickets")

      assert index_live |> element("#tickets-#{ticket.id} a", "Edit") |> render_click() =~
               "Edit Ticket"

      assert_patch(index_live, ~p"/tickets/#{ticket}/edit")

      assert index_live
             |> form("#ticket-form", ticket: %{subject: "Escalate this please", queue: "billing"})
             |> render_submit()

      assert_patch(index_live, ~p"/tickets")

      html = render(index_live)
      assert html =~ "Ticket updated"
      assert html =~ "Escalate this please"
    end

    test "resolves and reopens a ticket from the list", %{conn: conn} do
      ticket = ticket_fixture()
      {:ok, index_live, _html} = live(conn, ~p"/tickets")

      index_live |> element("#tickets-#{ticket.id} a", "Resolve") |> render_click()
      assert Tickets.get_ticket!(ticket.id).status == :resolved

      index_live |> element("#tickets-#{ticket.id} a", "Reopen") |> render_click()
      assert Tickets.get_ticket!(ticket.id).status == :new
    end

    test "deletes a ticket from the list", %{conn: conn} do
      ticket = ticket_fixture()
      {:ok, index_live, _html} = live(conn, ~p"/tickets")

      assert index_live |> element("#tickets-#{ticket.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#tickets-#{ticket.id}")
      assert_raise Ecto.NoResultsError, fn -> Tickets.get_ticket!(ticket.id) end
    end
  end

  describe "Show" do
    test "displays ticket details", %{conn: conn} do
      ticket = ticket_fixture()
      {:ok, _show_live, html} = live(conn, ~p"/tickets/#{ticket}")

      assert html =~ "Ticket ##{ticket.id}"
      assert html =~ ticket.subject
    end

    test "resolves and reopens a ticket from the detail page", %{conn: conn} do
      ticket = ticket_fixture()
      {:ok, show_live, _html} = live(conn, ~p"/tickets/#{ticket}")

      show_live |> element("button", "Resolve") |> render_click()
      assert Tickets.get_ticket!(ticket.id).status == :resolved
      assert render(show_live) =~ "resolved"

      show_live |> element("button", "Reopen") |> render_click()
      assert Tickets.get_ticket!(ticket.id).status == :new
    end

    test "edits a ticket from the detail page", %{conn: conn} do
      ticket = ticket_fixture()
      {:ok, show_live, _html} = live(conn, ~p"/tickets/#{ticket}")

      assert show_live |> element("a", "Edit") |> render_click() =~ "Edit Ticket"
      assert_patch(show_live, ~p"/tickets/#{ticket}/show/edit")

      assert show_live
             |> form("#ticket-form", ticket: %{subject: "Edited via show page"})
             |> render_submit()

      assert_patch(show_live, ~p"/tickets/#{ticket}")
      assert render(show_live) =~ "Edited via show page"
    end

    test "deletes a ticket from the detail page and redirects to the list", %{conn: conn} do
      ticket = ticket_fixture()
      {:ok, show_live, _html} = live(conn, ~p"/tickets/#{ticket}")

      {:error, {:live_redirect, %{to: path}}} =
        show_live |> element("button", "Delete") |> render_click()

      assert path == ~p"/tickets"
      assert_raise Ecto.NoResultsError, fn -> Tickets.get_ticket!(ticket.id) end
    end
  end
end
