defmodule Solo do
  @moduledoc """
  `Solo` is the library to turn parts of the existing supervision trees into singletons.

  Consider the application having the following children specified somewhere in the supervision tree.

  ```elixir
  children = [
    Foo,
    {Bar, [bar_arg]},
    {Baz, [baz_arg]},
    ...
  ]
  ```

  and there is a necessity to make `Bar` and `Baz` processes singletons across the cluster.
  Simply wrap the specs in question into `Solo.global/2` and you are all set.

  ```elixir
  children = [
    Foo,
    Solo.global(SoloBarBaz, [
      {Bar, [bar_arg]},
      {Baz, [baz_arg]}
    ],
    ...
  ]
  ```
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

    defexception [:action, :reason, :id, :message]

    @impl true
    def message(%{message: nil, id: id, reason: reason, action: action}) do
      """
      Could not #{action} the child (id: #{inspect(id)}) with reason: #{inspect(reason)}
      """
    end

    def message(%{message: message}), do: message
  end

  alias Solo.Watchdog

  use Supervisor

  @doc false
  def start_link(children, opts \\ []) do
    {name, _opts} = Keyword.pop(opts, :name, __MODULE__)

    with {:ok, pid} <- Supervisor.start_link(__MODULE__, children, name: name) do
      revalidate(name, pid)
      {:ok, pid}
    end
  end

  @doc section: :interface
  @doc """
  Helper to make parts of the supervision tree a global distributed singleton.

  Simply wrap the parts of any supervision tree with a call to `Solo.global/2`
  and you ar eall set.

  ```elixir
  children = [
    Foo,
    Solo.global(SoloBarBaz, [
      {Bar, [bar_arg]},
      {Baz, [baz_arg]}
    ],
    ...
  ]
  ```

  The name (`SoloBarBaz`) above might be used later to check the state of the
  running `Solo` supervisor with `Solo.state/1`, although this is usually not
  a demanded feature.

  To lookup the named processes turned into `Solo`, use `Solo.whereis/1`,
  passing the respective id (`SoloBarBaz`) and the actual name of the process.
  """
  def global(name \\ __MODULE__, children, opts \\ [timer: 1_000]) do
    %{
      id: {Solo, name},
      start: {Solo, :start_link, [children, Keyword.put_new(opts, :name, name)]},
      type: :supervisor
    }
  end

  @impl Supervisor
  @doc false
  def init(children) do
    Supervisor.init(
      [%{id: :pg, start: {__MODULE__, :start_pg, []}}, Watchdog | children_specs(children)],
      strategy: :one_for_one
    )
  end

  @doc false
  @spec revalidate(module(), pid()) :: :ok
  def revalidate(name, pid) when is_pid(pid) do
    %{watchdog: watchdog, pg: _pg, workers: workers} =
      pid
      |> Supervisor.which_children()
      |> Enum.reduce(%{workers: %{}}, fn
        {Watchdog, pid, _, _}, acc -> Map.put(acc, :watchdog, pid)
        {:pg, pid, _, _}, acc -> Map.put(acc, :pg, pid)
        {worker, pid, _, _}, acc -> put_in(acc, [:workers, pid], worker)
      end)

    GenServer.cast(watchdog, {:refs, %{workers: workers, supervisor: pid, name: name}})
    :pg.join(name, workers |> Map.keys() |> split_local_pids() |> elem(0))
  end

  @doc false
  def child_spec(args) do
    super(args)
  end

  @doc false
  def start_pg do
    with {:error, {:already_started, _pid}} <- :pg.start_link(), do: :ignore
  end

  @doc false
  def find(solo, id) do
    solo
    |> Supervisor.which_children()
    |> Enum.find(&match?({^id, _, _, _}, &1))
  end

  @doc false
  def children_specs(children) do
    Enum.map(children, &transform_child_spec/1)
  end

  defp transform_child_spec(%{id: id, start: {mod, fun, args}} = spec),
    do: %{spec | id: sup_name(id), start: {Solo, :start_child, [mod, fun, args]}}

  defp transform_child_spec({mod, args}) when is_atom(mod),
    do: args |> mod.child_spec() |> transform_child_spec()

  defp transform_child_spec(mod) when is_atom(mod),
    do: mod.child_spec() |> transform_child_spec()

  @doc false
  @spec split_local_pids(arg) :: {arg, arg} when arg: [pid]
  def split_local_pids(pids) when is_list(pids) do
    this = node()
    pids |> Enum.reject(&(&1 == :undefined)) |> Enum.split_with(&(:erlang.node(&1) == this))
  end

  @spec split_local_pids(arg) :: {arg, arg} when arg: %{optional(pid) => module()}
  def split_local_pids(pids_ids) when is_map(pids_ids) do
    this = node()

    pids_ids
    |> Map.reject(&match?({:undefined, _}, &1))
    |> Map.split_with(&(this == &1 |> elem(0) |> :erlang.node()))
  end

  @doc false
  def start_child(mod, fun, args) do
    name =
      case Keyword.get(args, :name) do
        nil -> {:global, Module.concat(mod, Sup)}
        {:global, name} when is_atom(name) -> {:global, sup_name(name)}
        name when is_atom(name) -> {:global, sup_name(name)}
        {:via, reg, id} -> raise UnsupportedName, reg: reg, id: id
      end

    children = [%{id: mod, start: {mod, fun, args}}]

    with {:error, {:already_started, pid}} <-
           Solo.Supervised.start_link(children: children, name: name),
         do: {:ok, pid}
  end

  @doc false
  def sup_name(mod) when is_atom(mod), do: Module.concat(mod, Sup)

  @doc section: :helpers
  @doc """
  Looks the process with the name given as the first parameter up.
  """
  @spec whereis(name :: atom()) :: pid()
  def whereis(name) do
    with [{^name, pid, _, _}] <-
           name |> sup_name() |> :global.whereis_name() |> Supervisor.which_children(),
         do: pid
  end

  @doc section: :helpers
  @doc """
  Returns the state of the `Solo` from this node’s perspective (pids of workers
  might be remote.)
  """
  @spec state(solo :: atom()) :: %{
          name: atom(),
          supervisor: pid(),
          pg: reference(),
          workers: %{optional(pid()) => atom()}
        }
  def state(solo \\ __MODULE__) do
    with {_, pid, _, _} <- Solo.find(solo, Watchdog), do: GenServer.call(pid, :state)
  end
end
