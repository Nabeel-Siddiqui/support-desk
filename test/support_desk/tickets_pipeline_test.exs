defmodule SupportDesk.TicketsPipelineTest do
  @moduledoc """
  DB-free tests for the ticket pipeline's pure pieces: the AI keyword
  fallback, the matcher, and the triage rules. None of these hit the
  database or the network, so they run offline and in CI without a repo.
  """
  use ExUnit.Case, async: false

  alias SupportDesk.Tickets.{AI, Matcher, Triage}

  describe "AI.fallback/2 (deterministic keyword matching)" do
    test "flags spam" do
      result =
        AI.fallback("You've won!", "Click here to claim your lottery winner prize, prince!")

      assert result.intent == "spam"
    end

    test "detects billing intent" do
      result = AI.fallback("Invoice question", "I was charged twice on my last invoice.")
      assert result.intent == "billing"
    end

    test "detects refund intent" do
      result = AI.fallback("Need my money back", "Please issue a refund for my last order.")
      assert result.intent == "refund"
    end

    test "detects cancellation intent" do
      result = AI.fallback("Leaving", "I want to cancel my subscription immediately.")
      assert result.intent == "cancellation"
    end

    test "detects account access intent" do
      result = AI.fallback("Locked out", "I can't sign in, my password isn't working.")
      assert result.intent == "account_access"
    end

    test "detects how_to intent" do
      result = AI.fallback("Question", "How do I export my data to CSV?")
      assert result.intent == "how_to"
    end

    test "falls back to other when nothing matches" do
      result = AI.fallback("Hello", "Just saying hi, no particular request here.")
      assert result.intent == "other"
    end

    test "detects very negative sentiment" do
      result = AI.fallback("Furious", "This is unacceptable, I am furious and disgusted.")
      assert result.sentiment == "very_negative"
    end

    test "detects negative sentiment" do
      result = AI.fallback("Annoyed", "I'm pretty frustrated and disappointed with this.")
      assert result.sentiment == "negative"
    end

    test "detects positive sentiment" do
      result = AI.fallback("Thanks!", "Thank you so much, this is great, I really appreciate it.")
      assert result.sentiment == "positive"
    end

    test "defaults to neutral sentiment" do
      result = AI.fallback("Question", "What time does support open on weekdays?")
      assert result.sentiment == "neutral"
    end

    test "detects critical urgency" do
      result = AI.fallback("URGENT", "This is an emergency, our production system is down.")
      assert result.urgency == "critical"
    end

    test "detects high urgency" do
      result = AI.fallback("Important", "This is fairly high priority, please look soon.")
      assert result.urgency == "high"
    end

    test "defaults to normal urgency" do
      result = AI.fallback("Hi", "No rush on this, whenever you get a chance.")
      assert result.urgency == "normal"
    end

    test "builds a one-line summary from the subject when present" do
      result = AI.fallback("Can't log in to my account", "Long body text here...")
      assert result.summary == "Can't log in to my account"
    end

    test "falls back to the first sentence of the body when subject is blank" do
      result = AI.fallback("", "My invoice looks wrong. There are extra charges on it.")
      assert result.summary == "My invoice looks wrong"
    end

    test "returns a mid-range confidence score" do
      result = AI.fallback("Hi", "hello")
      assert result.ai_confidence == 0.5
    end
  end

  describe "AI.analyze/1 without an API key" do
    test "falls back to keyword matching when ai_enabled is true but there is no API key" do
      original_enabled = Application.get_env(:support_desk, :ai_enabled)
      original_key = System.get_env("ANTHROPIC_API_KEY")

      Application.put_env(:support_desk, :ai_enabled, true)
      System.delete_env("ANTHROPIC_API_KEY")

      result = AI.analyze(%{subject: "Refund please", body: "I would like a refund."})
      assert result.intent == "refund"

      if is_nil(original_enabled) do
        Application.delete_env(:support_desk, :ai_enabled)
      else
        Application.put_env(:support_desk, :ai_enabled, original_enabled)
      end

      if original_key, do: System.put_env("ANTHROPIC_API_KEY", original_key)
    end
  end

  describe "Matcher.match/1" do
    setup do
      original_lookup = Application.get_env(:support_desk, :user_lookup)
      original_crm = Application.get_env(:support_desk, :crm_accounts)

      on_exit(fn ->
        if original_lookup do
          Application.put_env(:support_desk, :user_lookup, original_lookup)
        else
          Application.delete_env(:support_desk, :user_lookup)
        end

        if original_crm do
          Application.put_env(:support_desk, :crm_accounts, original_crm)
        else
          Application.delete_env(:support_desk, :crm_accounts)
        end
      end)

      Application.put_env(:support_desk, :crm_accounts, %{
        "acme.com" => %{name: "Acme Corp", tier: "enterprise", owner: "jane@support_desk.test"}
      })

      :ok
    end

    test "returns matched_user_id from the configured user_lookup function" do
      Application.put_env(:support_desk, :user_lookup, fn
        "known@example.com" -> %{id: 42}
        _ -> nil
      end)

      result = Matcher.match("known@example.com")
      assert result.matched_user_id == 42
      assert result.known_customer == true
    end

    test "returns nil matched_user_id when the lookup function finds nobody" do
      Application.put_env(:support_desk, :user_lookup, fn _ -> nil end)

      result = Matcher.match("nobody@example.com")
      assert result.matched_user_id == nil
    end

    test "skips user lookup entirely when unset" do
      Application.delete_env(:support_desk, :user_lookup)

      result = Matcher.match("someone@example.com")
      assert result.matched_user_id == nil
    end

    test "matches a CRM account by sender email domain" do
      Application.delete_env(:support_desk, :user_lookup)

      result = Matcher.match("bob@acme.com")
      assert result.crm_account["name"] == "Acme Corp"
      assert result.crm_account["tier"] == "enterprise"
      assert result.known_customer == true
    end

    test "returns nil crm_account and known_customer false for an unmatched domain" do
      Application.delete_env(:support_desk, :user_lookup)

      result = Matcher.match("someone@unknown-domain.com")
      assert result.crm_account == nil
      assert result.known_customer == false
    end
  end

  describe "Triage.decide/1" do
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
