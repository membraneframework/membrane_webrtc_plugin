defmodule Membrane.WebRTC.App do
  use Application

  def start(_opts, _args) do
    children = [{Registry, name: Membrane.WebRTC.WhipRegistry, keys: :unique}]
    Supervisor.start_link(children, strategy: :one_for_all, name: __MODULE__.Supervisor)
  end
end
