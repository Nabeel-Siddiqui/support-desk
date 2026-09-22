defmodule SupportDeskWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use SupportDeskWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint SupportDeskWeb.Endpoint

      use SupportDeskWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import SupportDeskWeb.ConnCase
    end
  end

  setup tags do
    SupportDesk.DataCase.setup_sandbox(tags)

    admin_auth = Application.fetch_env!(:support_desk, :admin_auth)
    auth_header = Plug.BasicAuth.encode_basic_auth(admin_auth[:username], admin_auth[:password])

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("authorization", auth_header)

    {:ok, conn: conn}
  end
end
