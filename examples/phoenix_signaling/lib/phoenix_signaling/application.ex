defmodule PhoenixSignaling.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PhoenixSignalingWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:phoenix_signaling, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PhoenixSignaling.PubSub},
      # Start a worker by calling: PhoenixSignaling.Worker.start_link(arg)
      # {PhoenixSignaling.Worker, arg},
      # Start to serve requests, typically the last entry
      PhoenixSignalingWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PhoenixSignaling.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PhoenixSignalingWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
