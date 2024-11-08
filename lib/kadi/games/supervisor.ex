defmodule Kadi.Games.Supervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok) do
    children = [
      # Registry to keep track of Game server sessions
      {Kadi.Registry, name: Kadi.Registry},
      # Dynamic supervisor to monitor game instances
      {DynamicSupervisor, name: Kadi.GameSupervisor, strategy: :one_for_one},
    ]

    # restart all if either the registry or dynamic supervisor dies
    Supervisor.init(children, strategy: :one_for_all)
  end
end
