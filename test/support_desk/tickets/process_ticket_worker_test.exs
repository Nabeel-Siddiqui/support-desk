defmodule SupportDesk.Tickets.ProcessTicketWorkerTest do
  use SupportDesk.DataCase, async: true
  use Oban.Testing, repo: SupportDesk.Repo

  import SupportDesk.TicketsFixtures

  alias SupportDesk.Tickets
  alias SupportDesk.Tickets.ProcessTicketWorker

  describe "perform/1" do
    test "processes the ticket with the given id" do
      ticket = ticket_fixture()

      assert :ok = perform_job(ProcessTicketWorker, %{ticket_id: ticket.id})

      processed = Tickets.get_ticket!(ticket.id)
      assert processed.status != :new
      assert processed.intent != nil
    end

    test "a ticket already processed is simply re-processed, not an error" do
      ticket = ticket_fixture()
      assert :ok = perform_job(ProcessTicketWorker, %{ticket_id: ticket.id})

      assert :ok = perform_job(ProcessTicketWorker, %{ticket_id: ticket.id})
    end
  end
end
