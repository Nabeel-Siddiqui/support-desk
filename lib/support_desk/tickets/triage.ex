defmodule SupportDesk.Tickets.Triage do
  @moduledoc """
  Decides what happens to a ticket: an ordered list of small rule
  functions, each returning `nil` (no match) or
  `%{status:, queue:, priority:, reason:}`. The first rule that matches
  wins.
  """

  @unhappy_sentiments ["negative", "very_negative"]
  @billing_intents ["billing", "refund", "cancellation"]
  @self_serve_intents ["how_to", "account_access"]
  @high_value_tiers ["enterprise", "pro"]

  @rules [
    :spam,
    :unhappy_high_value_customer,
    :critical_urgency,
    :very_negative,
    :billing_related,
    :confident_self_serve,
    :default_route
  ]

  @doc """
  Runs the ordered rules against a ticket-shaped map (expects `:intent`,
  `:sentiment`, `:urgency`, `:ai_confidence`, `:known_customer`,
  `:crm_account`) and returns the first match's
  `%{status:, queue:, priority:, reason:}`.
  """
  def decide(ticket) do
    Enum.find_value(@rules, &apply(__MODULE__, &1, [ticket]))
  end

  def spam(%{intent: "spam"}) do
    %{status: :auto_resolved, queue: "trash", priority: "p4", reason: "Detected as spam"}
  end

  def spam(_), do: nil

  def unhappy_high_value_customer(%{sentiment: sentiment, crm_account: %{"tier" => tier}})
      when sentiment in @unhappy_sentiments and tier in @high_value_tiers do
    %{
      status: :escalated,
      queue: "escalations",
      priority: "p1",
      reason: "Unhappy #{tier} customer (sentiment: #{sentiment})"
    }
  end

  def unhappy_high_value_customer(_), do: nil

  def critical_urgency(%{urgency: "critical"}) do
    %{status: :escalated, queue: "escalations", priority: "p1", reason: "Critical urgency"}
  end

  def critical_urgency(_), do: nil

  def very_negative(%{sentiment: "very_negative"}) do
    %{status: :escalated, queue: "escalations", priority: "p2", reason: "Very negative sentiment"}
  end

  def very_negative(_), do: nil

  def billing_related(%{intent: intent}) when intent in @billing_intents do
    %{
      status: :routed,
      queue: "billing",
      priority: "p3",
      reason: "Billing-related intent (#{intent})"
    }
  end

  def billing_related(_), do: nil

  def confident_self_serve(%{intent: intent, ai_confidence: confidence, sentiment: sentiment})
      when intent in @self_serve_intents and is_number(confidence) and confidence >= 0.75 and
             sentiment not in @unhappy_sentiments do
    %{
      status: :auto_resolved,
      queue: "kb_bot",
      priority: "p4",
      reason: "Confident (#{confidence}) self-serve intent (#{intent})"
    }
  end

  def confident_self_serve(_), do: nil

  def default_route(%{known_customer: known_customer}) do
    priority = if known_customer, do: "p3", else: "p4"

    %{
      status: :routed,
      queue: "general",
      priority: priority,
      reason: "No specific rule matched; routed to general queue"
    }
  end
end
