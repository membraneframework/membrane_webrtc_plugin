defmodule ExampleProjectWeb.Router do
  use ExampleProjectWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ExampleProjectWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ExampleProjectWeb do
    pipe_through(:browser)

    live("/", Live.EchoLive, :index)
  end

  # Other scopes may use custom stacks.
  # scope "/api", ExampleProjectWeb do
  #   pipe_through :api
  # end
end
