defmodule FountWeb.Router do
  use FountWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FountWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug FountWeb.OwnerAuth, :fetch_owner
  end

  pipeline :owner do
    plug FountWeb.OwnerAuth, :require_owner
  end

  scope "/", FountWeb do
    pipe_through :browser
    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  scope "/", FountWeb do
    pipe_through [:browser, :owner]

    post "/projects", ProjectController, :create

    live_session :owner, on_mount: [{FountWeb.OwnerAuth, :ensure_authenticated}] do
      live "/", ProjectLive, :index
      live "/projects/new", ProjectLive, :new
      live "/runs/:id/setup", RunLive, :setup
      live "/runs/:id/timeline", RunLive, :timeline
      live "/runs/:id/decisions", RunLive, :decisions
      live "/runs/:id/review", RunLive, :review
      live "/runs/:id/analysis", AnalysisLive, :show
      live "/runs/:id/viewer", ViewerLive, :show
      live "/runs/:id/edit", EditorLive, :edit
      live "/runs/:id/exports", RunLive, :exports
      live "/runs/:id/tools", ProductionLive, :show
    end

    get "/production/:run_id/notes.json", ProductionController, :notes
    get "/production/:run_id/table-reads/:id/export.json", ProductionController, :table_read
    get "/production/:run_id/usefulness.json", ProductionController, :usefulness

    get "/artifacts/:run_id/:delivery_id/preview", ArtifactController, :preview
    get "/artifacts/:run_id/:delivery_id", ArtifactController, :show
  end
end
