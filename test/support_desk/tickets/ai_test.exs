defmodule SupportDesk.Tickets.AITest do
  @moduledoc """
  DB-free tests for the AI module's deterministic keyword fallback —
  no database or network access, so these run offline and in CI
  without a repo.
  """
  use ExUnit.Case, async: false

  alias SupportDesk.Tickets.AI

  describe "fallback/2 (deterministic keyword matching)" do
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

  describe "analyze/1 without an API key" do
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
end
