defmodule Solo.Supervised do
  @moduledoc false
  use Supervisor

  def start_link(opts \\ []) do
    children = Keyword.fetch!(opts, :children)
    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, children, name: name)
  end

  @impl true
  def init(children) do
    Supervisor.init(children, strategy: :one_for_one)
  end
end
