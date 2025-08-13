defmodule PaymentProcessor.CoordinatorHealthCheck do
  @moduledoc """
  Health check process for coordinator connectivity.
  Monitors coordinator availability and logs connection issues.
  """
  use GenServer
  require Logger

  @check_interval 30_000  # 30 seconds
  @startup_delay 5_000    # 5 seconds initial delay

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @impl true
  def init(_state) do
    # Schedule initial health check after startup delay
    Process.send_after(self(), :health_check, @startup_delay)
    
    {:ok, %{last_check: nil, status: :unknown, consecutive_failures: 0}}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    {:reply, Map.take(state, [:status, :last_check, :consecutive_failures]), state}
  end

  @impl true
  def handle_info(:health_check, state) do
    new_state = perform_health_check(state)
    
    # Schedule next check
    Process.send_after(self(), :health_check, @check_interval)
    
    {:noreply, new_state}
  end

  defp perform_health_check(state) do
    case PaymentProcessor.CoordinatorClient.get_queue_status() do
      {:ok, _status} ->
        if state.consecutive_failures > 0 do
          Logger.info("Coordinator health restored after #{state.consecutive_failures} failures")
        end
        
        %{state | 
          status: :healthy, 
          last_check: DateTime.utc_now(), 
          consecutive_failures: 0
        }
        
      {:error, reason} ->
        consecutive_failures = state.consecutive_failures + 1
        
        if consecutive_failures == 1 do
          Logger.warning("Coordinator health check failed: #{inspect(reason)}")
        else
          if consecutive_failures >= 5 do
            Logger.error("Coordinator unreachable for #{consecutive_failures} consecutive checks")
          end
        end
        
        %{state | 
          status: :unhealthy, 
          last_check: DateTime.utc_now(), 
          consecutive_failures: consecutive_failures
        }
    end
  end
end