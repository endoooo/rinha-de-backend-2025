defmodule QueueCoordinator.Router do
  use Plug.Router
  require Logger

  plug Plug.Logger
  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :dispatch

  # Health check endpoint
  get "/health" do
    send_resp(conn, 200, Jason.encode!(%{status: "ok", service: "queue_coordinator"}))
  end

  # Enqueue payment for processing
  post "/enqueue-payment" do
    with {:ok, %{"correlationId" => correlation_id, "amount" => amount}} <- get_body_params(conn),
         {:ok, decimal_amount} <- parse_amount(amount) do
      
      requested_at = DateTime.utc_now()
      
      case QueueCoordinator.QueueManager.enqueue_payment(correlation_id, decimal_amount, requested_at) do
        :ok ->
          send_resp(conn, 201, Jason.encode!(%{status: "queued"}))
        {:error, :duplicate} ->
          send_resp(conn, 409, Jason.encode!(%{error: "Payment with this correlation ID already exists"}))
        {:error, reason} ->
          Logger.error("Failed to enqueue payment: #{inspect(reason)}")
          send_resp(conn, 500, Jason.encode!(%{error: "Failed to enqueue payment"}))
      end
    else
      {:error, :invalid_amount} ->
        send_resp(conn, 400, Jason.encode!(%{error: "Invalid amount"}))
      {:error, :missing_params} ->
        send_resp(conn, 400, Jason.encode!(%{error: "Missing required fields: correlationId, amount"}))
      _ ->
        send_resp(conn, 400, Jason.encode!(%{error: "Invalid request"}))
    end
  end

  # Get payments summary
  get "/payments-summary" do
    query_params = Plug.Conn.fetch_query_params(conn).query_params
    from_timestamp = parse_optional_timestamp(Map.get(query_params, "from"))
    to_timestamp = parse_optional_timestamp(Map.get(query_params, "to"))

    case {from_timestamp, to_timestamp} do
      {{:ok, from_ts}, {:ok, to_ts}} ->
        summary = QueueCoordinator.Storage.get_payments_summary(from_ts, to_ts)
        send_resp(conn, 200, Jason.encode!(summary))
      {{:error, _}, _} ->
        send_resp(conn, 400, Jason.encode!(%{error: "Invalid 'from' timestamp format"}))
      {_, {:error, _}} ->
        send_resp(conn, 400, Jason.encode!(%{error: "Invalid 'to' timestamp format"}))
    end
  end

  # Get queue status for monitoring
  get "/queue-status" do
    status = QueueCoordinator.QueueManager.get_status()
    send_resp(conn, 200, Jason.encode!(status))
  end

  # Catch-all for unmatched routes
  match _ do
    send_resp(conn, 404, Jason.encode!(%{error: "Not found"}))
  end

  defp get_body_params(conn) do
    case conn.body_params do
      %{"correlationId" => correlation_id, "amount" => amount} -> 
        {:ok, %{"correlationId" => correlation_id, "amount" => amount}}
      _ -> 
        {:error, :missing_params}
    end
  end

  defp parse_amount(amount) when is_number(amount) and amount > 0 do
    {:ok, Decimal.from_float(amount)}
  end

  defp parse_amount(amount) when is_binary(amount) do
    case Decimal.parse(amount) do
      {decimal, ""} when not is_nil(decimal) ->
        if Decimal.positive?(decimal), do: {:ok, decimal}, else: {:error, :invalid_amount}
      _ ->
        {:error, :invalid_amount}
    end
  end

  defp parse_amount(_), do: {:error, :invalid_amount}

  defp parse_optional_timestamp(nil), do: {:ok, nil}

  defp parse_optional_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _} -> {:ok, datetime}
      {:error, _} -> {:error, :invalid_timestamp}
    end
  end

  defp parse_optional_timestamp(_), do: {:error, :invalid_timestamp}
end