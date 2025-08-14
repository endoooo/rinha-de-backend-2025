defmodule QueueCoordinator.ProcessorHealthMonitor do
  @moduledoc """
  Monitors payment processor health and response times.
  Implements smart routing logic based on performance thresholds.
  """
  use GenServer
  require Logger

  @health_check_interval 5000 + :rand.uniform(50)  # 5s + jitter like competitor

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get_processor_status do
    GenServer.call(__MODULE__, :get_status)
  end

  def get_best_processor do
    GenServer.call(__MODULE__, :get_best_processor)
  end

  @impl true
  def init(_state) do
    # Start health checking immediately
    schedule_health_check()
    
    initial_state = %{
      # Only track fallback processor health - always try default first
      fallback: %{failing: false, min_response_time: 0, consecutive_failures: 0},
      last_check: DateTime.utc_now()
    }
    
    Logger.info("ProcessorHealthMonitor started")
    {:ok, initial_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:get_best_processor, _from, state) do
    best_processor = select_best_processor(state)
    {:reply, best_processor, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    # Schedule next check
    schedule_health_check()
    
    # Check both processors
    new_state = perform_health_checks(state)
    
    {:noreply, new_state}
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end

  defp perform_health_checks(state) do
    # Only check fallback processor health - default always attempted first
    fallback_status = check_processor_health(:fallback)
    
    new_state = %{
      fallback: update_processor_status(state.fallback, fallback_status),
      last_check: DateTime.utc_now()
    }
    
    Logger.debug("Health check results - Fallback: #{inspect(new_state.fallback)} (default always attempted)")
    
    new_state
  end

  defp check_processor_health(processor_type) do
    url = processor_url(processor_type)
    start_time = :os.system_time(:millisecond)
    
    request = Finch.build(:get, "#{url}/payments/service-health", [])
    
    case Finch.request(request, QueueCoordinator.HTTPClient, 
           pool_timeout: 200,      # More reasonable pool acquisition time
           receive_timeout: 2000,  # Back to safer timeout to prevent crashes
           request_timeout: 3000   # Total request timeout
         ) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        end_time = :os.system_time(:millisecond)
        response_time = end_time - start_time
        
        case Jason.decode(body) do
          {:ok, %{"failing" => failing, "minResponseTime" => min_response_time}} ->
            %{
              failing: failing,
              min_response_time: min_response_time,
              actual_response_time: response_time,
              success: true
            }
          {:error, _} ->
            %{failing: true, min_response_time: 999, actual_response_time: response_time, success: false}
        end
        
      {:ok, %Finch.Response{status: _status}} ->
        end_time = :os.system_time(:millisecond)
        response_time = end_time - start_time
        %{failing: true, min_response_time: 999, actual_response_time: response_time, success: false}
        
      {:error, _reason} ->
        %{failing: true, min_response_time: 999, actual_response_time: 999, success: false}
    end
  end

  defp update_processor_status(current_status, health_result) do
    case health_result do
      %{success: true, failing: failing, min_response_time: min_response_time} ->
        %{
          failing: failing,
          min_response_time: min_response_time,
          consecutive_failures: 0  # Reset on success
        }
        
      %{success: false} ->
        %{
          failing: true,
          min_response_time: 999,
          consecutive_failures: current_status.consecutive_failures + 1
        }
    end
  end

  defp select_best_processor(_state) do
    # Always return default processor - fallback handled as backup in routing logic
    {:ok, :default}
  end

  def is_fallback_available do
    GenServer.call(__MODULE__, :is_fallback_available)
  end

  @impl true
  def handle_call(:is_fallback_available, _from, state) do
    available = not state.fallback.failing and state.fallback.min_response_time <= 50
    {:reply, available, state}
  end

  defp processor_url(:default), do: "http://payment-processor-default:8080"
  defp processor_url(:fallback), do: "http://payment-processor-fallback:8080"
end