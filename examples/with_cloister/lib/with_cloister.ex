defmodule WithCloister do
  @moduledoc false

  defmodule GS do
    @moduledoc false
    use GenServer

    def start_link(opts \\ []) do
      {gs_opts, state} = Keyword.split(opts, [:name])
      GenServer.start_link(__MODULE__, state, gs_opts)
    end

    @impl GenServer
    def init(state), do: {:ok, state}
  end

  @behaviour Cloister.Listener
  require Logger

  @impl Cloister.Listener
  def on_state_change(from, to, %Cloister.Monitor{node: node, sentry?: sentry?}) do
    Logger.info(
      "Distributed cluster state has changed ‹#{from}› → ‹#{to}›, node: ‹#{node}›, sentry?: ‹#{sentry?}›"
    )
  end

  use Application
  @impl Application
  @doc false
  def start(_type \\ :normal, _args \\ []) do
    children =
      [
        Solo.global(Solo.WithCloister, [{WithCloister.Broadway, []}, {GS, name: GS}]) 
      ]

    opts = [strategy: :one_for_one, name: WithCloister.Application]

    Supervisor.start_link(children, opts)
  end
end
