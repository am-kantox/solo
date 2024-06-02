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

      {:ok, pid}
    end
  end

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

  To lookup the named processes turned into `Solo`, use `Solo.whereis/2`,
  passing the respective id (`SoloBarBaz`) and the actual name of the process.
  """
  def global(name \\ __MODULE__, children) do
    %{
      id: {Solo, name},
      start: {Solo, :start_link, [children, [name: name]]},
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

  @doc false
  def start_child(mod, fun, args) do
    name =
      case Keyword.get(args, :name) do
        nil -> {:global, mod}
        name when is_atom(name) -> {:global, name}
        {:via, reg, id} -> raise UnsupportedName, reg: reg, id: id
      end

    args = args |> unwind_keyword() |> Keyword.put(:name, name)
    with {:error, {:already_started, pid}} <- apply(mod, fun, [args]), do: {:ok, pid}
  end

  @spec unwind_keyword(keyword() | [keyword()]) :: keyword()
  defp unwind_keyword([kw]) when is_list(kw), do: unwind_keyword(kw)
  defp unwind_keyword(kw) when is_list(kw), do: kw

  @doc """
  Looks the process with the name given as the first parameter up.
  """
  @spec whereis(name :: atom()) :: pid()
  def whereis(name), do: :global.whereis_name(name)

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
