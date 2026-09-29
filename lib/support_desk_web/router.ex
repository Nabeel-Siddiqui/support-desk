defmodule SupportDeskWeb.Router do
  use SupportDeskWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SupportDeskWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    # This is an internal admin tool, not a public app — gate the whole
    # browser UI behind a shared credential. Swap for a real accounts
    # system (e.g. mix phx.gen.auth) if you need per-person attribution.
    plug :admin_auth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :webhook do
    plug SupportDeskWeb.Plugs.VerifyWebhookSecret
  end

  defp admin_auth(conn, _opts) do
    Plug.BasicAuth.basic_auth(conn, Application.fetch_env!(:support_desk, :admin_auth))
  end

  scope "/", SupportDeskWeb do
    pipe_through :browser

    live "/", HomeLive, :index

    live "/tickets", TicketLive.Index, :index
    live "/tickets/new", TicketLive.Index, :new
    live "/tickets/:id/edit", TicketLive.Index, :edit

    live "/tickets/:id", TicketLive.Show, :show
    live "/tickets/:id/show/edit", TicketLive.Show, :edit
  end

  scope "/webhooks", SupportDeskWeb do
    pipe_through [:api, :webhook]

    post "/inbound", WebhookController, :inbound
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:support_desk, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SupportDeskWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
