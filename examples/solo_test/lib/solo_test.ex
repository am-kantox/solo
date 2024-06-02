defmodule SoloTest do
  @moduledoc false

  for i <- 1..4//1 do
    defmodule :"Elixir.Srv#{i}" do
      use GenServer

      def start_link(_), do: GenServer.start_link(__MODULE__, :ok)

      @impl GenServer
      def init(:ok), do: {:ok, nil}
    end
  end

  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    children = [
      {Srv1, []},
      Solo.global(SoloSrv, [{Srv2, []}, {Srv3, []}]),
      {Srv4, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
