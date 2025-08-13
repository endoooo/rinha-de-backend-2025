defmodule PaymentProcessor.DistributedCoordinatorClient do
  @moduledoc """
  Distributed Erlang client for communicating with the queue coordinator service.
  Uses direct GenServer calls instead of HTTP for maximum performance.
  """
  require Logger
  alias PaymentProcessor.CoordinatorClient

  @coordinator_node :"queue_coordinator@coordinator"
  @queue_manager_process QueueCoordinator.QueueManager
  @storage_process QueueCoordinator.Storage

  def enqueue_payment(correlation_id, amount, requested_at) do
    Logger.info("Attempting distributed call to coordinator node: #{@coordinator_node}")
    Logger.info("Available nodes: #{inspect(Node.list())}")
    Logger.info("Current node: #{inspect(Node.self())}")
    
    # Check if coordinator node is connected
    if @coordinator_node in Node.list() do
      Logger.info("Coordinator node is connected, making GenServer.cast")
      try do
        # Try direct GenServer cast to coordinator (fire and forget for speed)
        GenServer.cast({@queue_manager_process, @coordinator_node}, 
          {:enqueue_payment, correlation_id, amount, requested_at})
        
        Logger.info("Distributed call succeeded")
        {:ok, :queued}
      rescue
        error ->
          Logger.error("Distributed coordinator call failed: #{inspect(error)}")
          {:error, :distributed_call_failed}
      end
    else
      Logger.warning("Coordinator node not in connected nodes list")
      Logger.info("Attempting to connect to coordinator...")
      
      case Node.connect(@coordinator_node) do
        true ->
          Logger.info("Successfully connected to coordinator, retrying cast")
          GenServer.cast({@queue_manager_process, @coordinator_node}, 
            {:enqueue_payment, correlation_id, amount, requested_at})
          {:ok, :queued}
        false ->
          Logger.error("Failed to connect to coordinator node")
          {:error, :connection_failed}
      end
    end
  end

  def get_payments_summary(from_timestamp \\ nil, to_timestamp \\ nil) do
    Logger.info("Getting payments summary via distributed call")
    
    if @coordinator_node in Node.list() do
      try do
        # Direct GenServer call to coordinator storage (use correct message format)
        result = GenServer.call({@storage_process, @coordinator_node}, 
          {:get_summary, from_timestamp, to_timestamp}, 5_000)
        
        {:ok, result}
      rescue
        error ->
          Logger.error("Distributed summary call failed: #{inspect(error)}")
          {:error, :distributed_call_failed}
      end
    else
      Logger.error("Coordinator node not connected for summary call")
      {:error, :not_connected}
    end
  end

  def get_queue_status do
    try do
      # Direct GenServer call to queue manager
      result = GenServer.call({@queue_manager_process, @coordinator_node}, :get_status, 5_000)
      {:ok, result}
    rescue
      error ->
        Logger.warning("Distributed status call failed: #{inspect(error)}")
        # Fallback to HTTP coordinator
        CoordinatorClient.get_queue_status()
    end
  end

  def coordinator_available? do
    @coordinator_node in Node.list()
  end

  def connect_to_coordinator do
    case Node.connect(@coordinator_node) do
      true -> 
        Logger.info("Successfully connected to coordinator node")
        :ok
      false -> 
        Logger.warning("Failed to connect to coordinator node")
        :error
    end
  end
end