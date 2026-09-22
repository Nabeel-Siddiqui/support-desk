defmodule SupportDeskWeb.WebhookController do
  use SupportDeskWeb, :controller

  require Logger

  alias SupportDesk.Tickets
  alias SupportDesk.Tickets.Ticket

  @doc """
  Receives an inbound message payload (`from`, `subject`, `text`/`html`,
  `message_id`), normalizes it into ticket intake attrs, and kicks off the
  ticket pipeline without blocking the response.

  A malformed payload (missing/unparseable sender, for example) is rejected
  synchronously with a 422 so the sender's retry logic actually finds out —
  we validate before accepting, since a fire-and-forget background job can't
  tell anyone it failed. A well-formed payload gets processed in a detached
  `Task` so the webhook still returns instantly (senders expect this, and it
  avoids holding the connection open through an AI call + several DB
  writes). This is where Oban would go instead, so a crashed run gets
  retried rather than silently dropped.
  """
  def inbound(conn, params) do
    attrs = normalize(params)
    changeset = Tickets.change_new_ticket(%Ticket{}, attrs)

    if changeset.valid? do
      Task.Supervisor.start_child(SupportDesk.TaskSupervisor, fn ->
        case Tickets.receive(attrs) do
          {:ok, _ticket_or_duplicate} ->
            :ok

          {:error, reason} ->
            Logger.error("webhook ticket pipeline failed",
              from_email: attrs.from_email,
              external_id: attrs.external_id,
              reason: inspect(reason)
            )
        end
      end)

      send_resp(conn, 200, "")
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{errors: changeset_errors(changeset)})
    end
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, &SupportDeskWeb.CoreComponents.translate_error/1)
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
