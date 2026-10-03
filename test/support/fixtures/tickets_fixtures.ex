defmodule SupportDesk.TicketsFixtures do
  @moduledoc """
  This module defines test helpers for creating entities via the
  `SupportDesk.Tickets` context.
  """

  alias SupportDesk.Tickets

  def valid_ticket_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      channel: "email",
      from_email: "customer@example.com",
      subject: "I want a refund",
      body: "Please refund my last order, I want to cancel."
    })
  end

  def ticket_fixture(attrs \\ %{}) do
    {:ok, ticket} = Tickets.create(valid_ticket_attributes(attrs))
    ticket
  end
end
