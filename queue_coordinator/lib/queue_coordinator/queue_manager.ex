defmodule QueueCoordinator.QueueManager do
  @moduledoc """
  Centralized queue manager for payment processing.
  Ensures ordered processing and prevents duplicates.
  """
  use GenServer
  require Logger

  @queue_table :payment_queue
  @dedup_table :payment_dedup

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def enqueue_payment(correlation_id, amount, requested_at) do
    GenServer.cast(__MODULE__, {:enqueue_payment, correlation_id, amount, requested_at})
  end

  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @impl true
  def init(_state) do
    Logger.info("Initializing queue manager")
    
    # Create ETS table for queue (ordered processing)
    :ets.new(@queue_table, [
      :ordered_set, 
      :public, 
      :named_table,
      {:write_concurrency, true}
    ])
    
    # Create ETS table for deduplication
    :ets.new(@dedup_table, [
      :set, 
      :public, 
      :named_table
    ])
    
    # Start processing
    send(self(), :process_batch)
    
    {:ok, %{processing: false, active_workers: 0, max_workers: 6}}
  end

  @impl true
  def handle_cast({:enqueue_payment, correlation_id, amount, requested_at}, state) do
    Logger.info("Received distributed payment enqueue: #{correlation_id}, amount: #{amount}")
    
    # Check for duplicates
    case :ets.insert_new(@dedup_table, {correlation_id, true}) do
      true ->
        # Add to queue with timestamp for ordering
        timestamp = :os.system_time(:microsecond)
        :ets.insert(@queue_table, {timestamp, {correlation_id, amount, requested_at}})
        
        # Trigger batch processing if not already processing
        if not state.processing do
          send(self(), :process_batch)
        end
        
        {:noreply, state}
      false ->
        # Still enqueue duplicate to maintain order, but mark as duplicate
        timestamp = :os.system_time(:microsecond)
        :ets.insert(@queue_table, {timestamp, {:duplicate, correlation_id, amount, requested_at}})
        
        if not state.processing do
          send(self(), :process_batch)
        end
        
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    queue_size = :ets.info(@queue_table, :size)
    status = %{
      queue_size: queue_size,
      processing: state.processing,
      active_workers: state.active_workers,
      max_workers: state.max_workers
    }
    {:reply, status, state}
  end

  @impl true
  def handle_info(:process_batch, state) do
    # Get available worker slots
    available_slots = state.max_workers - state.active_workers
    
    if available_slots > 0 do
      batch = get_next_batch(min(available_slots, 4))  # Process up to 4 at once
      
      if Enum.empty?(batch) do
        # No work to do
        Process.send_after(self(), :process_batch, 50)  # Check again in 50ms
        {:noreply, %{state | processing: false}}
      else
        # Start concurrent workers for batch
        new_workers = Enum.count(batch)
        
        Enum.each(batch, fn {timestamp, payment} ->
          Task.Supervisor.start_child(QueueCoordinator.TaskSupervisor, fn ->
            process_payment_concurrent(timestamp, payment)
            # Notify completion
            GenServer.cast(__MODULE__, :worker_completed)
          end)
        end)
        
        # Continue processing
        send(self(), :process_batch)
        {:noreply, %{state | processing: true, active_workers: state.active_workers + new_workers}}
      end
    else
      # All workers busy, check again shortly
      Process.send_after(self(), :process_batch, 10)
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_cast(:worker_completed, state) do
    new_active_workers = max(0, state.active_workers - 1)
    
    # Trigger more processing if queue has items
    if new_active_workers < state.max_workers and :ets.info(@queue_table, :size) > 0 do
      send(self(), :process_batch)
    end
    
    {:noreply, %{state | active_workers: new_active_workers}}
  end

  defp get_next_batch(count) do
    get_next_batch(count, [])
  end
  
  defp get_next_batch(0, acc), do: Enum.reverse(acc)
  defp get_next_batch(count, acc) do
    case :ets.first(@queue_table) do
      :"$end_of_table" -> 
        Enum.reverse(acc)
      timestamp -> 
        case :ets.lookup(@queue_table, timestamp) do
          [{^timestamp, payment}] -> 
            :ets.delete(@queue_table, timestamp)
            get_next_batch(count - 1, [{timestamp, payment} | acc])
          [] -> 
            # Race condition, try again
            get_next_batch(count, acc)
        end
    end
  end
  
  defp process_payment_concurrent(timestamp, {:duplicate, correlation_id, _amount, _requested_at}) do
    Logger.debug("Skipping duplicate payment: #{correlation_id}")
  end
  
  defp process_payment_concurrent(_timestamp, {correlation_id, amount, requested_at}) do
    process_payment(correlation_id, amount, requested_at)
  end

  defp process_payment(correlation_id, amount, requested_at) do
    case route_payment(correlation_id, amount, requested_at) do
      {:ok, processor_used} ->
        payment_data = %{
          correlation_id: correlation_id,
          amount: amount,
          processor_used: processor_used,
          status: "success",
          processed_at: requested_at
        }
        QueueCoordinator.Storage.store_payment(payment_data)
        Logger.debug("Payment processed successfully: #{correlation_id}")
        
      {:error, reason} ->
        Logger.warning("Payment processing failed: #{correlation_id}, reason: #{inspect(reason)}")
        payment_data = %{
          correlation_id: correlation_id,
          amount: amount,
          processor_used: "none",
          status: "failed",
          processed_at: requested_at
        }
        QueueCoordinator.Storage.store_payment(payment_data)
    end
  end

  defp route_payment(correlation_id, amount, requested_at) do
    # Smart health-based processor selection (like competitor)
    case QueueCoordinator.ProcessorHealthMonitor.get_best_processor() do
      {:ok, processor_type} ->
        Logger.info("Health monitor selected processor: #{processor_type} for payment #{correlation_id}")
        case make_payment_request(processor_type, correlation_id, amount, requested_at) do
          {:ok, _response} ->
            Logger.info("Payment #{correlation_id} succeeded with #{processor_type}")
            {:ok, to_string(processor_type)}
          {:error, reason} ->
            # Respect health monitor decision - no backup attempts
            # Only use processors that pass health criteria
            Logger.warning("Payment #{correlation_id} failed with #{processor_type}: #{inspect(reason)}")
            {:error, reason}
        end
        
      {:skip, :all_processors_slow} ->
        # Skip processing when both processors are slow (better than using slow processor)
        Logger.warning("Skipping payment #{correlation_id} - all processors too slow")
        {:error, :all_processors_slow}
    end
  end

  defp make_payment_request(processor_type, correlation_id, amount, requested_at) do
    url = processor_url(processor_type)
    
    # Handle different types of requested_at values
    iso_timestamp = case requested_at do
      %DateTime{} -> DateTime.to_iso8601(requested_at)
      timestamp when is_binary(timestamp) -> timestamp
      _ -> 
        Logger.warning("Invalid requested_at format, using current time")
        DateTime.to_iso8601(DateTime.utc_now())
    end
    
    body = Jason.encode!(%{
      correlationId: correlation_id,
      amount: amount,
      requestedAt: iso_timestamp
    })
    
    headers = [{"content-type", "application/json"}]
    request = Finch.build(:post, "#{url}/payments", headers, body)
    
    # Simple single attempt - no retries
    case Finch.request(request, QueueCoordinator.HTTPClient, 
           pool_timeout: 100,      # Fast pool acquisition
           receive_timeout: 1000,  # Single attempt timeout
           request_timeout: 1500   # Total request timeout
         ) do
      {:ok, %Finch.Response{status: status}} when status in 200..299 ->
        {:ok, :success}
      {:ok, %Finch.Response{status: status}} ->
        {:error, {:http_error, status}}
      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  defp processor_url(:default), do: "http://payment-processor-default:8080"
  defp processor_url(:fallback), do: "http://payment-processor-fallback:8080"
end