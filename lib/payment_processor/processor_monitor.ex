defmodule PaymentProcessor.ProcessorMonitor do
  use GenServer
  alias PaymentProcessor.ProcessorClient

  @check_interval 5_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get_status(processor_type) do
    GenServer.call(__MODULE__, {:get_status, processor_type})
  end

  @impl true
  def init(state) do
    schedule_health_check()
    {:ok, %{default: :unknown, fallback: :unknown}}
  end

  @impl true
  def handle_call({:get_status, processor_type}, _from, state) do
    {:reply, Map.get(state, processor_type, :unknown), state}
  end

  @impl true
  def handle_info(:health_check, state) do
    # Perform health checks asynchronously to avoid blocking
    parent = self()

    spawn(fn ->
      default_status = check_processor(:default)
      send(parent, {:health_result, :default, default_status})
    end)

    spawn(fn ->
      fallback_status = check_processor(:fallback)
      send(parent, {:health_result, :fallback, fallback_status})
    end)

    schedule_health_check()
    {:noreply, state}
  end

  @impl true
  def handle_info({:health_result, processor_type, status}, state) do
    new_state = Map.put(state, processor_type, status)
    {:noreply, new_state}
  end

  defp check_processor(type) do
    case ProcessorClient.health_check(type) do
      {:ok, _} -> :healthy
      {:error, _} -> :unhealthy
    end
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @check_interval)
  end
end
