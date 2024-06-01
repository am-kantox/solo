defmodule Solo.Watchdog do
  @moduledoc false

  use GenServer

  require Logger

  def start_link(opts \\ []) do
    {name, opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, Map.new(opts), name)
  end

  @impl GenServer
  def init(state) do
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  @impl GenServer
  def handle_cast({:refs, %{name: name} = refs}, %{} = state) do
    {ref, pids} = :pg.monitor(name)
    Enum.each(pids, &Process.monitor/1)
    {:noreply, state |> Map.merge(refs) |> Map.put(:pg, ref)}
  end

  @impl GenServer
  def handle_info({ref, :join, group, pids}, %{pg: ref, name: group} = state) do
    Enum.each(pids, &Process.monitor/1)
    {:noreply, state}
  end

  def handle_info({ref, :leave, group, pids}, %{pg: ref, name: group} = state) do
    workers =
      Enum.reduce(pids, state.workers, fn pid, acc ->
        {id, acc} = Map.pop!(acc, pid)

        case maybe_restart_child(id, state) do
          pid when is_pid(pid) -> Map.put(acc, pid, id)
          nil -> acc
        end
      end)

    {:noreply, %{state | workers: workers}}
  end

  @impl GenServer
  def handle_info({:DOWN, _, :process, pid, :normal}, %{workers: %{} = workers} = state) do
    workers = Map.delete(workers, pid)

    if workers == %{},
      do: {:stop, :normal, %{state | workers: %{}}},
      else: {:noreply, %{state | workers: workers}}
  end

  def handle_info({:DOWN, _, :process, pid, _reason}, %{} = state) do
    # Managed process exited with an error. Try restarting, after a delay
    # Process.sleep(:rand.uniform(1_000) + 1_000)

    id = Map.get(state.workers, pid)

    state =
      case maybe_restart_child(id, state) do
        pid when is_pid(pid) -> put_in(state, [:workers, pid], id)
        nil -> state
      end

    {:noreply, state}
  end

  defp maybe_restart_child(id, state) do
    with {_, pid, _, _} <- Solo.find(state.supervisor, id),
         true <- :rpc.call(node(pid), :erlang, :is_process_alive, [pid]) do
      pid
    else
      _ -> restart_child(id, state)
    end
  end

  defp restart_child(id, %{supervisor: supervisor, name: group} = state) do
    case Supervisor.restart_child(supervisor, id) do
      {:error, :restarting} ->
        restart_child(id, state)

      {:error, :running} ->
        Supervisor.terminate_child(supervisor, id)
        restart_child(id, state)

      {:ok, pid} ->
        if node(pid) == node(), do: :pg.join(group, [pid])
        pid

      {:error, reason} ->
        # raise Solo.UnreliableChild, id: id, reason: reason
        Logger.warning(
          "Error restarting child ‹" <> inspect(id) <> "›, reason: ‹" <> inspect(reason) <> "›"
        )

        nil
    end
  end
end
