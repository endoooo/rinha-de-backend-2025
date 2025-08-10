defmodule PaymentProcessor.ProcessorMonitor do
  use GenServer
  alias PaymentProcessor.ProcessorClient

  @check_interval 10_000

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
    new_state = %{
      default: check_processor(:default),
      fallback: check_processor(:fallback)
    }
    
    schedule_health_check()
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