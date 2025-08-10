defmodule PaymentProcessor.DeduplicationCache do
  use GenServer
  
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  def check_and_mark(correlation_id) do
    GenServer.call(__MODULE__, {:check_and_mark, correlation_id})
  end
  
  @impl true
  def init(_state) do
    :ets.new(:payment_dedup, [:set, :public, :named_table])
    {:ok, %{}}
  end
  
  @impl true
  def handle_call({:check_and_mark, correlation_id}, _from, state) do
    case :ets.insert_new(:payment_dedup, {correlation_id, true}) do
      true -> {:reply, :ok, state}
      false -> {:reply, :duplicate, state}
    end
  end
end