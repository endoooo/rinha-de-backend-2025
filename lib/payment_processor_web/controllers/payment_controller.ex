defmodule PaymentProcessorWeb.PaymentController do
  use PaymentProcessorWeb, :controller
  alias PaymentProcessor.CoordinatorClient

  def health(conn, _params) do
    json(conn, %{status: "ok", service: "payment_processor"})
  end

  def create(conn, %{"correlationId" => correlation_id, "amount" => amount}) do
    with {:ok, uuid} <- validate_uuid(correlation_id),
         {:ok, decimal_amount} <- validate_amount(amount) do
      # Send payment to coordinator for queuing and processing
      requested_at = DateTime.utc_now()
      
      case CoordinatorClient.enqueue_payment(uuid, decimal_amount, requested_at) do
        {:ok, :queued} ->
          # Return success immediately after queuing
          conn
          |> put_status(:created)
          |> json(%{status: "success"})

        {:error, :duplicate} ->
          conn
          |> put_status(:conflict)
          |> json(%{error: "Payment with this correlation ID already exists"})

        {:error, _reason} ->
          conn
          |> put_status(:service_unavailable)
          |> json(%{error: "Payment processing service unavailable"})
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
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required fields: correlationId, amount"})
  end

  def summary(conn, params) do
    with {:ok, from_ts} <- parse_optional_timestamp(Map.get(params, "from")),
         {:ok, to_ts} <- parse_optional_timestamp(Map.get(params, "to")) do
      case CoordinatorClient.get_payments_summary(from_ts, to_ts) do
        {:ok, summary} ->
          json(conn, summary)
        {:error, _reason} ->
          conn
          |> put_status(:service_unavailable)
          |> json(%{error: "Summary service unavailable"})
      end
    else
      {:error, :invalid_timestamp} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid timestamp format"})
    end
  end

  defp validate_uuid(correlation_id) when is_binary(correlation_id) do
    # Simple UUID validation using regex
    uuid_regex = ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    if Regex.match?(uuid_regex, correlation_id) do
      {:ok, correlation_id}
    else
      {:error, :invalid_uuid}
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

  defp parse_optional_timestamp(nil), do: {:ok, nil}

  defp parse_optional_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _} -> {:ok, datetime}
      {:error, _} -> {:error, :invalid_timestamp}
    end
  end

  defp parse_optional_timestamp(_), do: {:error, :invalid_timestamp}
end
