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
    GenServer.call(__MODULE__, {:enqueue_payment, correlation_id, amount, requested_at})
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
    send(self(), :process_next)
    
    {:ok, %{processing: false}}
  end

  @impl true
  def handle_call({:enqueue_payment, correlation_id, amount, requested_at}, _from, state) do
    # Check for duplicates
    case :ets.insert_new(@dedup_table, {correlation_id, true}) do
      true ->
        # Add to queue with timestamp for ordering
        timestamp = :os.system_time(:microsecond)
        :ets.insert(@queue_table, {timestamp, {correlation_id, amount, requested_at}})
        
        # Trigger processing if not already processing
        if not state.processing do
          send(self(), :process_next)
        end
        
        {:reply, :ok, state}
      false ->
        {:reply, {:error, :duplicate}, state}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    queue_size = :ets.info(@queue_table, :size)
    status = %{
      queue_size: queue_size,
      processing: state.processing
    }
    {:reply, status, state}
  end

  @impl true
  def handle_info(:process_next, state) do
    case get_next_payment() do
      nil ->
        # No payments to process
        {:noreply, %{state | processing: false}}
        
      {timestamp, {correlation_id, amount, requested_at}} ->
        # Remove from queue
        :ets.delete(@queue_table, timestamp)
        
        # Process payment
        process_payment(correlation_id, amount, requested_at)
        
        # Schedule next processing
        send(self(), :process_next)
        {:noreply, %{state | processing: true}}
    end
  end

  defp get_next_payment do
    case :ets.first(@queue_table) do
      :"$end_of_table" -> nil
      timestamp -> 
        case :ets.lookup(@queue_table, timestamp) do
          [{^timestamp, payment}] -> {timestamp, payment}
          [] -> nil  # Race condition, already deleted
        end
    end
  end

  defp process_payment(correlation_id, amount, requested_at) do
    Logger.debug("Processing payment: #{correlation_id}")
    
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
    # Try default processor first, fallback on failure
    case make_payment_request(:default, correlation_id, amount, requested_at) do
      {:ok, _response} ->
        {:ok, "default"}
      {:error, _reason} ->
        case make_payment_request(:fallback, correlation_id, amount, requested_at) do
          {:ok, _response} ->
            {:ok, "fallback"}
          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp make_payment_request(processor_type, correlation_id, amount, requested_at) do
    url = processor_url(processor_type)
    
    body = Jason.encode!(%{
      correlationId: correlation_id,
      amount: amount,
      requestedAt: DateTime.to_iso8601(requested_at)
    })
    
    headers = [{"content-type", "application/json"}]
    request = Finch.build(:post, "#{url}/payments", headers, body)
    
    case Finch.request(request, QueueCoordinator.HTTPClient, receive_timeout: 3000) do
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