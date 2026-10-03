defmodule SupportDesk.Tickets.TriageTest do
  @moduledoc """
  DB-free tests for the Triage module's rule ordering — no database or
  network access, so these run offline and in CI without a repo.
  """
  use ExUnit.Case, async: false

  alias SupportDesk.Tickets.Triage

  describe "decide/1" do
    defp ticket(overrides) do
      Map.merge(
        %{
          intent: "other",
          sentiment: "neutral",
          urgency: "normal",
          ai_confidence: 0.5,
          known_customer: false,
          crm_account: nil
        },
        overrides
      )
    end

    test "spam wins even over other signals" do
      decision =
        ticket(%{intent: "spam", urgency: "critical", sentiment: "very_negative"})
        |> Triage.decide()

      assert decision.status == :auto_resolved
      assert decision.queue == "trash"
    end

    test "unhappy enterprise customer is escalated at p1" do
      decision =
        ticket(%{sentiment: "negative", crm_account: %{"tier" => "enterprise"}})
        |> Triage.decide()

      assert decision.status == :escalated
      assert decision.priority == "p1"
    end

    test "unhappy pro customer is escalated at p1" do
      decision =
        ticket(%{sentiment: "very_negative", crm_account: %{"tier" => "pro"}})
        |> Triage.decide()

      assert decision.status == :escalated
      assert decision.priority == "p1"
    end

    test "an unhappy customer on a free/unknown tier does not get the p1 escalation" do
      decision =
        ticket(%{sentiment: "negative", crm_account: %{"tier" => "free"}})
        |> Triage.decide()

      refute decision.priority == "p1"
    end

    test "critical urgency is escalated at p1" do
      decision = ticket(%{urgency: "critical"}) |> Triage.decide()

      assert decision.status == :escalated
      assert decision.priority == "p1"
    end

    test "very negative sentiment (without critical urgency or a high-value account) escalates at p2" do
      decision = ticket(%{sentiment: "very_negative"}) |> Triage.decide()

      assert decision.status == :escalated
      assert decision.priority == "p2"
    end

    test "billing intent routes to the billing queue at p3" do
      decision = ticket(%{intent: "billing"}) |> Triage.decide()

      assert decision.status == :routed
      assert decision.queue == "billing"
      assert decision.priority == "p3"
    end

    test "refund intent routes to the billing queue" do
      decision = ticket(%{intent: "refund"}) |> Triage.decide()
      assert decision.queue == "billing"
    end

    test "cancellation intent routes to the billing queue" do
      decision = ticket(%{intent: "cancellation"}) |> Triage.decide()
      assert decision.queue == "billing"
    end

    test "a confident how_to question auto-resolves via the KB bot" do
      decision = ticket(%{intent: "how_to", ai_confidence: 0.9}) |> Triage.decide()

      assert decision.status == :auto_resolved
      assert decision.queue == "kb_bot"
      assert decision.priority == "p4"
    end

    test "a confident account_access question auto-resolves via the KB bot" do
      decision = ticket(%{intent: "account_access", ai_confidence: 0.75}) |> Triage.decide()

      assert decision.status == :auto_resolved
      assert decision.queue == "kb_bot"
    end

    test "a low-confidence how_to question does not auto-resolve" do
      decision = ticket(%{intent: "how_to", ai_confidence: 0.5}) |> Triage.decide()

      refute decision.status == :auto_resolved
    end

    test "a negative how_to question does not auto-resolve, even if confident" do
      decision =
        ticket(%{intent: "how_to", ai_confidence: 0.9, sentiment: "negative"})
        |> Triage.decide()

      refute decision.status == :auto_resolved
    end

    test "known customers with no other match are routed to general at p3" do
      decision = ticket(%{known_customer: true}) |> Triage.decide()

      assert decision.status == :routed
      assert decision.queue == "general"
      assert decision.priority == "p3"
    end

    test "unknown senders with no other match are routed to general at p4" do
      decision = ticket(%{known_customer: false}) |> Triage.decide()

      assert decision.status == :routed
      assert decision.queue == "general"
      assert decision.priority == "p4"
    end
  end
end
