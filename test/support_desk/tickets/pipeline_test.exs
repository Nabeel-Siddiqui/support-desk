defmodule SupportDesk.Tickets.PipelineTest do
  use SupportDesk.DataCase, async: true

  alias SupportDesk.Tickets
  alias SupportDesk.Tickets.{Pipeline, Ticket}

  defp ticket_fixture(attrs \\ %{}) do
    {:ok, ticket} =
      attrs
      |> Enum.into(%{
        channel: "email",
        from_email: "customer@example.com",
        subject: "I want a refund",
        body: "Please refund my last order, I want to cancel."
      })
      |> Tickets.create()

    ticket
  end

  describe "process/1" do
    test "commits analysis, matching, and triage results together" do
      ticket = ticket_fixture()

      assert {:ok, processed} = Pipeline.process(ticket)

      assert processed.intent in ["refund", "cancellation"]
      assert processed.sentiment != nil
      assert processed.urgency != nil
      assert processed.known_customer == false
      assert processed.status in [:routed, :escalated, :auto_resolved]
      assert processed.queue != nil

      # and it's really persisted, not just returned in-memory
      reloaded = Tickets.get_ticket!(ticket.id)
      assert reloaded.status == processed.status
      assert reloaded.intent == processed.intent
    end

    test "routes billing/refund/cancellation tickets to the billing queue" do
      ticket = ticket_fixture(%{subject: "Cancel my subscription", body: "cancel cancellation"})

      assert {:ok, processed} = Pipeline.process(ticket)

      assert processed.queue == "billing"
      assert processed.status == :routed
    end

    test "marks the ticket :failed instead of crashing when a step raises" do
      ticket = ticket_fixture()

      # Sabotage the ticket's from_email after creation so Matcher.match/1
      # (which calls String.split/3 on it) blows up on a non-binary value —
      # simulates "something downstream raised mid-pipeline".
      broken_ticket = %{ticket | from_email: nil}

      assert {:ok, failed} = Pipeline.process(broken_ticket)
      assert failed.status == :failed

      reloaded = Tickets.get_ticket!(ticket.id)
      assert reloaded.status == :failed
    end
  end

  describe "receive/1" do
    test "creates and processes a new ticket" do
      assert {:ok, %Ticket{} = ticket} =
               Pipeline.receive(%{
                 channel: "email",
                 external_id: "msg-1",
                 from_email: "new@example.com",
                 subject: "How do I reset my password?",
                 body: "How do I reset my password?"
               })

      assert ticket.status != :new
      assert ticket.external_id == "msg-1"
    end

    test "treats a redelivered external_id as success instead of an error" do
      attrs = %{
        channel: "email",
        external_id: "dup-1",
        from_email: "dup@example.com",
        subject: "Hello",
        body: "Hello"
      }

      assert {:ok, %Ticket{}} = Pipeline.receive(attrs)
      assert {:ok, :duplicate} = Pipeline.receive(attrs)

      # only one row was actually created
      assert Tickets.list_tickets() |> Enum.count(&(&1.external_id == "dup-1")) == 1
    end

    test "returns a changeset error for a genuinely invalid payload" do
      assert {:error, changeset} =
               Pipeline.receive(%{channel: "email", from_email: "not-an-email"})

      assert "must be a valid email address" in errors_on(changeset).from_email
    end
  end
end
