defmodule WithCloister.Broadway do
  use Broadway

  alias Broadway.Message

  defmodule Producer do
    @moduledoc false
    use GenStage
    
    def start_link(opts) do
      GenStage.start_link(__MODULE__, opts)
    end

    @impl GenStage
    @doc false
    def init(state), do: {:producer, state}

    @impl GenStage
    def handle_demand(_demand, state) do
      msg =
        %Broadway.Message{
          data: "some data here",
          acknowledger: Broadway.NoopAcknowledger.init()
        }
      {:noreply, [msg], state}
    end
  end

  def start_link(_opts) do
    Broadway.start_link(WithCloister.Broadway,
      name: WithCloister.Broadway,
      producer: [
        module: {Producer, []},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 2]
      ],
      batchers: []
    )
  end

  @impl true
  def handle_message(_, %Message{data: _data} = message, _) do
    Message.update_data(message, &process_data/1)
  end

  defp process_data(data) do
    data
  end
end
