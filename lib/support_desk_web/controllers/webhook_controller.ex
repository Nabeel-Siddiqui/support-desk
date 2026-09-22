defmodule SupportDeskWeb.WebhookController do
  use SupportDeskWeb, :controller

  require Logger

  alias SupportDesk.Tickets

  @doc """
  Receives an inbound message payload (`from`, `subject`, `text`/`html`,
  `message_id`), normalizes it into ticket intake attrs, and kicks off the
  ticket pipeline without blocking the response.

  Runs the pipeline in a detached `Task` so the webhook always gets an
  instant 200 (senders like this, and it avoids holding a connection open
  through an AI call + DB writes). This is where Oban would go instead, so
  a crashed run gets retried rather than silently dropped.
  """
  def inbound(conn, params) do
    attrs = normalize(params)

    Task.Supervisor.start_child(SupportDesk.TaskSupervisor, fn ->
      case Tickets.receive(attrs) do
        {:ok, _ticket_or_duplicate} ->
          :ok

        {:error, reason} ->
          Logger.error("Webhook ticket pipeline failed: #{inspect(reason)}")
      end
    end)

    send_resp(conn, 200, "")
  end

  defp normalize(params) do
    {from_name, from_email} = parse_from(params["from"])

    %{
      channel: params["channel"] || "email",
      external_id: params["message_id"],
      from_email: from_email,
      from_name: from_name,
      subject: params["subject"],
      body: params["text"] || params["html"]
    }
  end

  @from_regex ~r/^\s*(?:"?(?<name>[^"<]*?)"?\s*)?<(?<email>[^<>]+)>\s*$/

  defp parse_from(nil), do: {nil, nil}

  defp parse_from(from) when is_binary(from) do
    case Regex.named_captures(@from_regex, from) do
      %{"name" => name, "email" => email} ->
        name = String.trim(name)
        {if(name == "", do: nil, else: name), String.trim(email)}

      nil ->
        {nil, String.trim(from)}
    end
  end
end
