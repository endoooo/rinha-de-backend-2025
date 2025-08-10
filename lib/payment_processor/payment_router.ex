defmodule PaymentProcessor.PaymentRouter do
  alias PaymentProcessor.{ProcessorMonitor, ProcessorClient}

  def route_payment(correlation_id, amount) do
    case select_processor() do
      :default -> 
        attempt_payment(:default, correlation_id, amount)
      :fallback -> 
        attempt_payment(:fallback, correlation_id, amount)
      :none ->
        {:error, :no_processors_available}
    end
  end

  defp select_processor do
    default_status = ProcessorMonitor.get_status(:default)
    fallback_status = ProcessorMonitor.get_status(:fallback)

    case {default_status, fallback_status} do
      {:healthy, _} -> :default
      {:unhealthy, :healthy} -> :fallback
      {_, :healthy} -> :fallback
      _ -> :none
    end
  end

  defp attempt_payment(processor_type, correlation_id, amount) do
    case ProcessorClient.process_payment(processor_type, correlation_id, amount) do
      {:ok, response} ->
        {:ok, processor_type, response}
      {:error, _reason} = error ->
        if processor_type == :default do
          attempt_payment(:fallback, correlation_id, amount)
        else
          error
        end
    end
  end
end