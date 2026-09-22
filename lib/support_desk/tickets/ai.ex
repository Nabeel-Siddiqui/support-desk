defmodule SupportDesk.Tickets.AI do
  @moduledoc """
  Extracts intent, sentiment, urgency, a one-line summary, and a confidence
  score from a ticket's subject/body.

  Calls Claude via tool use when `config :support_desk, :ai_enabled` is true
  and `ANTHROPIC_API_KEY` is set. Falls back to deterministic keyword
  matching otherwise (missing key, API error, or AI disabled), so this
  always runs offline and in tests.
  """

  require Logger

  @model "claude-haiku-4-5-20251001"
  @api_url "https://api.anthropic.com/v1/messages"
  @anthropic_version "2023-06-01"

  @intents ~w(billing refund cancellation bug_report how_to feature_request account_access complaint spam other)
  @sentiments ~w(very_negative negative neutral positive)
  @urgencies ~w(low normal high critical)

  @tool %{
    "name" => "extract_ticket_signals",
    "description" => "Extract structured support-ticket signals from a customer message.",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "intent" => %{
          "type" => "string",
          "enum" => @intents,
          "description" => "The primary reason the customer is reaching out."
        },
        "sentiment" => %{
          "type" => "string",
          "enum" => @sentiments,
          "description" => "The customer's emotional tone."
        },
        "urgency" => %{
          "type" => "string",
          "enum" => @urgencies,
          "description" => "How urgently this needs a response."
        },
        "summary" => %{
          "type" => "string",
          "description" => "A one-line (<=140 char) summary of the ticket."
        },
        "confidence" => %{
          "type" => "number",
          "description" => "Confidence in this analysis, from 0.0 to 1.0."
        }
      },
      "required" => ["intent", "sentiment", "urgency", "summary", "confidence"]
    }
  }

  @doc """
  Analyzes a ticket's subject/body and returns
  `%{intent:, sentiment:, urgency:, summary:, ai_confidence:}`.
  """
  def analyze(%{subject: subject, body: body}) do
    if enabled?() and api_key() do
      case call_claude(subject, body) do
        {:ok, result} ->
          result

        {:error, reason} ->
          Logger.warning("Claude tool-use call failed, falling back to keyword matching",
            reason: inspect(reason)
          )

          fallback(subject, body)
      end
    else
      fallback(subject, body)
    end
  end

  defp enabled?, do: Application.get_env(:support_desk, :ai_enabled, false)
  defp api_key, do: System.get_env("ANTHROPIC_API_KEY")

  defp call_claude(subject, body) do
    text = "Subject: #{subject}\n\nBody:\n#{body}"

    request_body = %{
      "model" => @model,
      "max_tokens" => 512,
      "tools" => [@tool],
      "tool_choice" => %{"type" => "tool", "name" => "extract_ticket_signals"},
      "messages" => [
        %{
          "role" => "user",
          "content" => "Analyze this customer support message:\n\n#{text}"
        }
      ]
    }

    req =
      Req.new(
        url: @api_url,
        headers: [
          {"x-api-key", api_key()},
          {"anthropic-version", @anthropic_version}
        ],
        json: request_body,
        receive_timeout: 15_000,
        # Retries connection errors, timeouts, 429s, and 5xxs with backoff —
        # a single Claude request timing out shouldn't fail the whole ticket.
        retry: :transient,
        max_retries: 2
      )

    case Req.post(req) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        extract_tool_input(body)

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        {:error, {:http_error, status, resp_body}}

      {:error, exception} ->
        {:error, exception}
    end
  rescue
    exception -> {:error, exception}
  end

  defp extract_tool_input(%{"content" => content}) when is_list(content) do
    case Enum.find(content, &(&1["type"] == "tool_use")) do
      %{"input" => input} ->
        {:ok,
         %{
           intent: input["intent"],
           sentiment: input["sentiment"],
           urgency: input["urgency"],
           summary: input["summary"],
           ai_confidence: input["confidence"] * 1.0
         }}

      nil ->
        {:error, :no_tool_use_block}
    end
  end

  defp extract_tool_input(_), do: {:error, :unexpected_response_shape}

  # --- Deterministic keyword fallback (offline / no API key / API errors) ---

  # Multi-word entries are plain string literals (not `~w`) on purpose:
  # `~w` would split "close my account" into "close", "my", "account", and
  # short fragments like "my" or "in" false-match almost any message.
  @spam_words ~w(viagra crypto lottery winner casino prince inheritance)
  @refund_words ["refund", "reimburse", "reimbursement", "money back"]
  @cancellation_words [
    "cancel",
    "cancellation",
    "unsubscribe",
    "close my account",
    "terminate my account"
  ]
  @billing_words ~w(billing invoice charge charged overcharged subscription payment)
  @bug_words [
    "bug",
    "broken",
    "error",
    "crash",
    "crashing",
    "fails",
    "failing",
    "not working",
    "doesn't work"
  ]
  @how_to_words ["how do i", "how can i", "how to", "tutorial", "guide"]
  @account_words [
    "password",
    "login",
    "log in",
    "locked out",
    "account access",
    "can't sign in",
    "cannot sign in"
  ]
  @feature_words ["feature request", "suggestion", "would be nice", "wish there was"]

  @very_negative_words ~w(furious outraged unacceptable disgusted terrible awful worst scam fraud)
  @negative_words ~w(frustrated annoyed disappointed unhappy upset angry)
  @positive_words ["thanks", "thank you", "great", "awesome", "love", "appreciate", "happy"]

  @critical_words ~w(urgent critical emergency asap immediately down outage)
  @high_words ["soon", "important", "priority"]

  def fallback(subject, body) do
    text = String.downcase("#{subject} #{body}")

    intent = detect_intent(text)
    sentiment = detect_sentiment(text)
    urgency = detect_urgency(text)
    summary = build_summary(subject, body)

    %{
      intent: intent,
      sentiment: sentiment,
      urgency: urgency,
      summary: summary,
      ai_confidence: 0.5
    }
  end

  defp detect_intent(text) do
    cond do
      contains_any?(text, @spam_words) -> "spam"
      contains_any?(text, @refund_words) -> "refund"
      contains_any?(text, @cancellation_words) -> "cancellation"
      contains_any?(text, @billing_words) -> "billing"
      contains_any?(text, @account_words) -> "account_access"
      contains_any?(text, @bug_words) -> "bug_report"
      contains_any?(text, @how_to_words) -> "how_to"
      contains_any?(text, @feature_words) -> "feature_request"
      contains_any?(text, ["complain", "complaint"]) -> "complaint"
      true -> "other"
    end
  end

  defp detect_sentiment(text) do
    cond do
      contains_any?(text, @very_negative_words) -> "very_negative"
      contains_any?(text, @negative_words) -> "negative"
      contains_any?(text, @positive_words) -> "positive"
      true -> "neutral"
    end
  end

  defp detect_urgency(text) do
    cond do
      contains_any?(text, @critical_words) -> "critical"
      contains_any?(text, @high_words) -> "high"
      true -> "normal"
    end
  end

  defp contains_any?(text, words), do: Enum.any?(words, &String.contains?(text, &1))

  defp build_summary(subject, body) do
    base = if present?(subject), do: subject, else: first_sentence(body)

    base
    |> to_string()
    |> String.trim()
    |> String.slice(0, 140)
  end

  defp present?(nil), do: false
  defp present?(str), do: String.trim(str) != ""

  defp first_sentence(nil), do: ""

  defp first_sentence(body) do
    body
    |> String.split(~r/[.!?\n]/, parts: 2)
    |> List.first()
    |> to_string()
  end
end
