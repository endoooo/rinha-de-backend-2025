defmodule QueueCoordinator.Storage do
  @moduledoc """
  Centralized storage for payment records and summaries.
  Single source of truth for all payment data.
  """
  use GenServer
  require Logger

  @payments_table :coordinator_payments_storage
  @summary_table :coordinator_summary_storage

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def store_payment(payment_data) do
    GenServer.call(__MODULE__, {:store_payment, payment_data})
  end

  def get_payments_summary(from_timestamp \\ nil, to_timestamp \\ nil) do
    GenServer.call(__MODULE__, {:get_summary, from_timestamp, to_timestamp})
  end

  def get_payment_by_correlation_id(correlation_id) do
    GenServer.call(__MODULE__, {:get_payment, correlation_id})
  end

  @impl true
  def init(_opts) do
    Logger.info("Initializing coordinator storage")
    
    # Create ETS table for payments
    :ets.new(@payments_table, [
      :set, 
      :public, 
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
    
    # Create ETS table for summary counters
    :ets.new(@summary_table, [
      :set, 
      :public, 
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
    
    # Initialize summary counters
    :ets.insert(@summary_table, {"default_total_requests", 0})
    :ets.insert(@summary_table, {"default_total_amount", Decimal.new(0)})
    :ets.insert(@summary_table, {"fallback_total_requests", 0})
    :ets.insert(@summary_table, {"fallback_total_amount", Decimal.new(0)})
    
    {:ok, %{}}
  end

  @impl true
  def handle_call({:store_payment, payment_data}, _from, state) do
    %{
      correlation_id: correlation_id,
      amount: amount,
      processor_used: processor_used,
      status: status,
      processed_at: processed_at
    } = payment_data

    # Store payment record
    payment_record = {
      correlation_id,
      amount,
      processor_used,
      status,
      processed_at
    }
    
    :ets.insert(@payments_table, {correlation_id, payment_record})
    
    # Update summary counters if payment successful
    if status == "success" do
      update_summary_counters(processor_used, amount)
    end
    
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:get_payment, correlation_id}, _from, state) do
    result = case :ets.lookup(@payments_table, correlation_id) do
      [{^correlation_id, payment_record}] -> {:ok, payment_record}
      [] -> {:error, :not_found}
    end
    
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_summary, from_timestamp, to_timestamp}, _from, state) do
    summary = if from_timestamp || to_timestamp do
      calculate_filtered_summary(from_timestamp, to_timestamp)
    else
      get_cached_summary()
    end
    
    {:reply, summary, state}
  end

  defp update_summary_counters(processor_used, amount) do
    requests_key = "#{processor_used}_total_requests"
    amount_key = "#{processor_used}_total_amount"
    
    # Update request count atomically
    :ets.update_counter(@summary_table, requests_key, 1)
    
    # Update total amount atomically
    update_amount_atomically(amount_key, amount)
  end

  defp update_amount_atomically(amount_key, amount) do
    case :ets.lookup(@summary_table, amount_key) do
      [{^amount_key, current_amount}] ->
        new_amount = Decimal.add(current_amount, amount)
        # Use select_replace for atomic compare-and-swap
        match_spec = [{
          {amount_key, current_amount},
          [],
          [{{amount_key, new_amount}}]
        }]
        
        case :ets.select_replace(@summary_table, match_spec) do
          1 -> :ok  # Successfully updated
          0 -> 
            # Value changed between lookup and update, retry
            update_amount_atomically(amount_key, amount)
        end
      [] ->
        # Initialize if doesn't exist (shouldn't happen due to init)
        :ets.insert(@summary_table, {amount_key, amount})
    end
  end

  defp get_cached_summary do
    [{_, default_requests}] = :ets.lookup(@summary_table, "default_total_requests")
    [{_, default_amount}] = :ets.lookup(@summary_table, "default_total_amount")
    [{_, fallback_requests}] = :ets.lookup(@summary_table, "fallback_total_requests")
    [{_, fallback_amount}] = :ets.lookup(@summary_table, "fallback_total_amount")
    
    %{
      "default" => %{
        "totalRequests" => default_requests,
        "totalAmount" => default_amount
      },
      "fallback" => %{
        "totalRequests" => fallback_requests,
        "totalAmount" => fallback_amount
      }
    }
  end

  defp calculate_filtered_summary(from_timestamp, to_timestamp) do
    payments = :ets.tab2list(@payments_table)
    
    filtered_payments = Enum.filter(payments, fn {_correlation_id, {_cid, _amount, _processor, status, processed_at}} ->
      status == "success" and within_time_range?(processed_at, from_timestamp, to_timestamp)
    end)
    
    Enum.reduce(filtered_payments, initial_summary(), fn {_correlation_id, {_cid, amount, processor, _status, _processed_at}}, acc ->
      processor_key = processor
      current_data = acc[processor_key]
      
      Map.put(acc, processor_key, %{
        "totalRequests" => current_data["totalRequests"] + 1,
        "totalAmount" => Decimal.add(current_data["totalAmount"], amount)
      })
    end)
  end

  defp within_time_range?(processed_at, from_timestamp, to_timestamp) do
    from_check = if from_timestamp, do: DateTime.compare(processed_at, from_timestamp) != :lt, else: true
    to_check = if to_timestamp, do: DateTime.compare(processed_at, to_timestamp) != :gt, else: true
    from_check and to_check
  end

  defp initial_summary do
    %{
      "default" => %{"totalRequests" => 0, "totalAmount" => Decimal.new(0)},
      "fallback" => %{"totalRequests" => 0, "totalAmount" => Decimal.new(0)}
    }
  end
end