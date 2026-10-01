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

    live_session :owner, on_mount: [{FountWeb.OwnerAuth, :ensure_authenticated}] do
      live "/", ProjectLive, :index
      live "/new", ProjectLive, :new
      live "/help", HelpLive, :index

      live "/p/:key", ViewerLive, :show
      live "/p/:key/write", EditorLive, :edit
      live "/p/:key/work", ProjectToolsLive, :work
      live "/p/:key/changes", ProjectToolsLive, :changes
      live "/p/:key/notes", ProjectToolsLive, :notes
      live "/p/:key/analysis", ProjectToolsLive, :analysis
      live "/p/:key/cast", ProjectToolsLive, :cast
      live "/p/:key/read", ProjectToolsLive, :read
      live "/p/:key/history", ProjectToolsLive, :history
      live "/p/:key/exports", ProjectToolsLive, :exports
      live "/p/:key/activity", ProjectToolsLive, :activity
      live "/p/:key/settings", ProjectToolsLive, :settings

      live "/p/:key/source/:task_key", TaskSourceLive, :show
      live "/p/:key/activity/:task_key", RunLive, :timeline
      live "/p/:key/activity/:task_key/setup", RunLive, :setup
      live "/p/:key/activity/:task_key/decisions", RunLive, :decisions
      live "/p/:key/changes/:task_key", RunLive, :review
      live "/p/:key/analysis/:task_key", AnalysisLive, :show
      live "/p/:key/exports/:task_key", RunLive, :exports
      live "/p/:key/tools/:task_key", ProductionLive, :show
    end

    get "/p/:key/tools/:task_key/notes.json", ProductionController, :notes
    get "/p/:key/tools/:task_key/table-reads/:read_ref/export.json", ProductionController, :table_read
    get "/p/:key/tools/:task_key/usefulness.json", ProductionController, :usefulness

    get "/p/:key/exports/:task_key/:delivery_ref/preview", ArtifactController, :preview
    get "/p/:key/exports/:task_key/:delivery_ref/download", ArtifactController, :show
  end
end
