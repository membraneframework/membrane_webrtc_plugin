defmodule Membrane.WebRTC.App do
  @moduledoc false
  use Application

  @spec start(term(), term()) :: Supervisor.on_start()
  def start(_opts, _args) do
    children = [
      {Registry, name: Membrane.WebRTC.WhipRegistry, keys: :unique},
      Membrane.WebRTC.PhoenixSignaling
    ]

    Supervisor.start_link(children, strategy: :one_for_all, name: __MODULE__.Supervisor)
  end
end
