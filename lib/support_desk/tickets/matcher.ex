defmodule SupportDesk.Tickets.Matcher do
  @moduledoc """
  Matches a ticket's sender against an internal user (via an optional
  configured lookup function) and against a CRM account (via a configured
  domain map).
  """

  @doc """
  Returns `%{matched_user_id:, crm_account:, known_customer:}` for the
  given sender email.
  """
  def match(from_email) when is_binary(from_email) do
    matched_user_id = lookup_user(from_email)
    crm_account = lookup_crm_account(from_email)

    %{
      matched_user_id: matched_user_id,
      crm_account: crm_account,
      known_customer: not is_nil(matched_user_id) or not is_nil(crm_account)
    }
  end

  # Skipped entirely when unset, so this module has no compile-time
  # dependency on the host app's Accounts context.
  defp lookup_user(email) do
    case Application.get_env(:support_desk, :user_lookup) do
      nil ->
        nil

      lookup_fun when is_function(lookup_fun, 1) ->
        case lookup_fun.(email) do
          %{id: id} -> id
          nil -> nil
          _ -> nil
        end
    end
  end

  defp lookup_crm_account(email) do
    with [_local, domain] <- String.split(email, "@", parts: 2),
         accounts when is_map(accounts) <- Application.get_env(:support_desk, :crm_accounts, %{}),
         %{} = account <- Map.get(accounts, String.downcase(domain)) do
      # Stringify keys so this matches the shape we get back after the map
      # round-trips through the :map (jsonb) column, whose keys always
      # decode as strings.
      Map.new(account, fn {k, v} -> {to_string(k), v} end)
    else
      _ -> nil
    end
  end
end
