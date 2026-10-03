defmodule SupportDesk.Tickets.MatcherTest do
  @moduledoc """
  DB-free tests for the Matcher module — no database or network
  access, so these run offline and in CI without a repo.
  """
  use ExUnit.Case, async: false

  alias SupportDesk.Tickets.Matcher

  describe "match/1" do
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
end
