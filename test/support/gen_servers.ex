defmodule Counter do
  @moduledoc false

  use GenServer

  def start_link(opts \\ []) do
    {initial, opts} = Keyword.pop(opts, :initial, 0)
    GenServer.start_link(__MODULE__, initial, opts)
  end

  @impl GenServer
  def init(initial), do: {:ok, initial}

  @impl GenServer
  def handle_cast(:inc, state) do
    {:noreply, state + 1}
  end

  @impl GenServer
  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end
end
