defmodule Solo do
  @moduledoc """
  Documentation for `Solo`.
  """

  defmodule UnsupportedName do
    @moduledoc false

    defexception [:reg, :id, :message]

    @impl true
    def message(%{message: nil, id: id, reg: reg}) do
      """
      The sinlgleton process is implemented with `:global` module
        which required the name to be an atom.

      `{:via, Registry, id}` names are not therefore supported.

      Tried to declare a name via `#{inspect(reg)}` with `#{inspect(id)}`
      """
    end

    def message(%{message: message}), do: message
  end

  defmodule UnreliableChild do
    @moduledoc false

    defexception [:reason, :id, :message]

    @impl true
    def message(%{message: nil, id: id, reason: reason}) do
      """
      Could not restart the child (id: #{inspect(id)}) with reason: #{inspect(reason)}
      """
    end

    def message(%{message: message}), do: message
  end

  alias Solo.Watchdog

  use Supervisor

  @doc """
  """

  def start_link(children, opts \\ []) do
    {name, _opts} = Keyword.pop(opts, :name, __MODULE__)

    with {:ok, pid} <- Supervisor.start_link(__MODULE__, children, name: name) do
      %{watchdog: watchdog, pg: _pg, workers: workers} =
        pid
        |> Supervisor.which_children()
        |> Enum.reduce(%{workers: %{}}, fn
          {Solo.Watchdog, pid, _, _}, acc -> Map.put(acc, :watchdog, pid)
          {:pg, pid, _, _}, acc -> Map.put(acc, :pg, pid)
          {worker, pid, _, _}, acc -> put_in(acc, [:workers, pid], worker)
        end)

      GenServer.cast(watchdog, {:refs, %{workers: workers, supervisor: pid, name: name}})
      :pg.join(name, workers |> Map.keys() |> split_local_pids() |> elem(0))

      {:ok, pid}
    end
  end

  @impl Supervisor
  def init(children) do
    Supervisor.init(
      [%{id: :pg, start: {__MODULE__, :start_pg, []}}, Watchdog | children_specs(children)],
      strategy: :one_for_one
    )
  end

  def start_pg do
    with {:error, {:already_started, _pid}} <- :pg.start_link(), do: :ignore
  end

  def find(pid, id) do
    pid
    |> Supervisor.which_children()
    |> Enum.find(&match?({^id, _, _, _}, &1))
  end

  def children_specs(children) do
    Enum.map(children, &transform_child_spec/1)
  end

  defp transform_child_spec(%{start: {mod, fun, args}} = spec),
    do: %{spec | start: {Solo, :start_child, [mod, fun, args]}}

  defp transform_child_spec({mod, args}) when is_atom(mod),
    do: args |> mod.child_spec() |> transform_child_spec()

  defp transform_child_spec(mod) when is_atom(mod),
    do: mod.child_spec() |> transform_child_spec()

  defp split_local_pids(pids) do
    this = node()
    pids |> Enum.reject(&(&1 == :undefined)) |> Enum.split_with(&(:erlang.node(&1) == this))
  end

  def start_child(mod, fun, [[{name, _} | _] = args]) when is_atom(name) do
    name =
      case Keyword.get(args, :name) do
        nil -> {:global, mod}
        name when is_atom(name) -> {:global, name}
        {:via, reg, id} -> raise UnsupportedName, reg: reg, id: id
      end

    # [AM] make sure (maybe with a custom compiler) name is used by the underlying `mod.fun/n`
    args = Keyword.put(args, :name, name)

    with {:error, {:already_started, pid}} <- apply(mod, fun, [args]), do: {:ok, pid}
  end

  def whereis(name), do: :global.whereis_name(name)

  def state do
    with {_, pid, _, _} <- Solo.find(Solo, Solo.Watchdog), do: GenServer.call(pid, :state)
  end
end
