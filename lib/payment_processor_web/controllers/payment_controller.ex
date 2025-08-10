defmodule PaymentProcessorWeb.PaymentController do
  use PaymentProcessorWeb, :controller
  alias PaymentProcessor.{PaymentRouter, Payments}

  def create(conn, %{"correlationId" => correlation_id, "amount" => amount}) do
    with {:ok, uuid} <- validate_uuid(correlation_id),
         {:ok, decimal_amount} <- validate_amount(amount),
         nil <- Payments.get_payment_by_correlation_id(uuid),
         {:ok, processor_used, _response} <- PaymentRouter.route_payment(uuid, decimal_amount) do
      
      payment_attrs = %{
        correlation_id: uuid,
        amount: decimal_amount,
        processor_used: Atom.to_string(processor_used),
        status: "success",
        processed_at: DateTime.utc_now()
      }
      
      case Payments.create_payment(payment_attrs) do
        {:ok, _payment} ->
          conn
          |> put_status(:created)
          |> json(%{status: "success"})
        
        {:error, _changeset} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Failed to record payment"})
      end
    else
      {:error, :invalid_uuid} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid correlation ID format"})
      
      {:error, :invalid_amount} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid amount"})
      
      %Payments.Payment{} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Payment with this correlation ID already exists"})
      
      {:error, :no_processors_available} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "No payment processors available"})
      
      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Payment processing failed"})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required fields: correlationId, amount"})
  end

  def summary(conn, params) do
    timestamp = case Map.get(params, "timestamp") do
      nil -> nil
      ts -> parse_timestamp(ts)
    end

    case timestamp do
      {:error, :invalid_timestamp} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid timestamp format"})
      
      parsed_timestamp ->
        summary = Payments.get_payments_summary(parsed_timestamp)
        json(conn, summary)
    end
  end

  defp validate_uuid(correlation_id) when is_binary(correlation_id) do
    case Ecto.UUID.cast(correlation_id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid_uuid}
    end
  end
  defp validate_uuid(_), do: {:error, :invalid_uuid}

  defp validate_amount(amount) when is_number(amount) and amount > 0 do
    {:ok, Decimal.from_float(amount)}
  end
  defp validate_amount(amount) when is_binary(amount) do
    case Decimal.parse(amount) do
      {decimal, ""} when not is_nil(decimal) ->
        if Decimal.positive?(decimal), do: {:ok, decimal}, else: {:error, :invalid_amount}
      _ ->
        {:error, :invalid_amount}
    end
  end
  defp validate_amount(_), do: {:error, :invalid_amount}

  defp parse_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _} -> datetime
      {:error, _} -> {:error, :invalid_timestamp}
    end
  end
  defp parse_timestamp(_), do: {:error, :invalid_timestamp}
end