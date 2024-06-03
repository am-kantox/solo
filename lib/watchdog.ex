defmodule Solo.Watchdog do
  @moduledoc false

  use GenServer

  require Logger

  def start_link(opts \\ []) do
    {name, opts} = Keyword.split(opts, [:name])

    opts =
      opts
      |> Map.new()
      |> Map.put_new(:timer, 0)

    GenServer.start_link(__MODULE__, opts, name)
  end

  @impl GenServer
  def init(state) do
    scheduled = state |> Map.fetch!(:timer) |> schedule_work()
    {:ok, Map.put(state, :scheduled, scheduled)}
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
    Logger.debug("[♚] #{Enum.count(pids)} process(es) joined group #{inspect(group)}")

    Enum.each(pids, &Process.monitor/1)
    {:noreply, state}
  end

  def handle_info({ref, :leave, group, pids}, %{pg: ref, name: group} = state) do
    Logger.debug("[♚] #{Enum.count(pids)} process(es) left group #{inspect(group)}")

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
    Logger.debug("[♚] #{inspect(pid)} (#{inspect(Map.get(workers, pid))}) is down as ‹:normal›")

    workers = Map.delete(workers, pid)

    if workers == %{},
      do: {:stop, :normal, %{state | workers: %{}}},
      else: {:noreply, %{state | workers: workers}}
  end

  def handle_info({:DOWN, _, :process, pid, reason}, %{workers: %{} = workers} = state) do
    id = Map.get(workers, pid)
    Logger.debug("[♚] #{inspect(pid)} (#{inspect(id)}) is down as ‹#{reason}›")

    state =
      case maybe_restart_child(id, state) do
        pid when is_pid(pid) -> put_in(state, [:workers, pid], id)
        nil -> state
      end

    {:noreply, state}
  end

  def handle_info(:work, %{workers: workers} = state) do
    workers
    |> Solo.split_local_pids()
    |> elem(0)
    |> Enum.reject(&(&1 |> elem(0) |> Process.alive?()))
    |> case do
      [] ->
        :ok

      ids ->
        Logger.error(
          Solo.UnreliableChild.message(%Solo.UnreliableChild{
            id: ids,
            action: :lookup,
            reason: :not_alive
          })
        )

        Solo.revalidate(state.name, state.supervisor)
    end

    scheduled = state |> Map.fetch!(:timer) |> schedule_work()
    {:noreply, Map.put(state, :scheduled, scheduled)}
  end

  defp maybe_restart_child(id, state) do
    with {_, pid, _, _} when is_pid(pid) <- Solo.find(state.supervisor, id),
         true <- :rpc.call(node(pid), :erlang, :is_process_alive, [pid]) do
      pid
    else
      # {_, :undefined, _, _} -> when in Supervisor.terminate_child/2
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
        Logger.debug("[♚] restarting child #{inspect(id)} (group #{inspect(group)})")
        if node(pid) == node(), do: :pg.join(group, [pid])
        pid

      {:error, reason} ->
        # raise Solo.UnreliableChild, id: id, reason: reason
        Logger.warning(
          "[♚] error restarting child ‹" <>
            inspect(id) <> "›, reason: ‹" <> inspect(reason) <> "›"
        )

        nil
    end
  end

  @spec schedule_work(timeout :: integer()) :: reference()
  defp schedule_work(timeout) when not is_integer(timeout) or timeout <= 0, do: make_ref()
  defp schedule_work(timeout), do: Process.send_after(self(), :work, timeout)
end
