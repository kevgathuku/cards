defmodule Kadi.Supervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok) do
    # Registry to keep track of Game server sessions
    children = [
      {Kadi.Registry, name: Kadi.Registry}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
