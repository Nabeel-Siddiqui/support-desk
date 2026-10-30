defmodule SupportDeskWeb.WebhookController do
  use SupportDeskWeb, :controller

  alias SupportDesk.Tickets
  alias SupportDesk.Tickets.Ticket

  @doc """
  Receives an inbound message payload (`from`, `subject`, `text`/`html`,
  `message_id`), normalizes it into ticket intake attrs, and creates the
  ticket.

  A malformed payload (missing/unparseable sender, for example) is
  rejected with a 422 so the sender's retry logic actually finds out.
  A well-formed one is saved and its processing job enqueued in one
  transaction (see `Pipeline.receive/1`), which is fast enough —
  milliseconds, not however long the AI call takes — to do inline and
  still answer instantly; the slow analyze -> match -> triage pipeline
  itself runs via `ProcessTicketWorker` (Oban), not on this request.
  """
  def inbound(conn, params) do
    attrs = normalize(params)

    with {:ok, _changeset} <- validate(attrs),
         {:ok, _ticket_or_duplicate} <- Tickets.receive(attrs) do
      send_resp(conn, 200, "")
    else
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: changeset_errors(changeset)})
    end
  end

  defp validate(attrs) do
    changeset = Tickets.change_new_ticket(%Ticket{}, attrs)
    if changeset.valid?, do: {:ok, changeset}, else: {:error, changeset}
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
