defmodule PaymentProcessor.HTTPServer do
  @moduledoc """
  Lightweight HTTP server using Bandit directly, replacing Phoenix framework.
  Optimized for minimal latency and maximum throughput.
  """
  use Plug.Router
  require Logger

  alias PaymentProcessor.DistributedCoordinatorClient

  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :dispatch

  # Health check endpoint
  get "/health" do
    send_resp(conn, 200, Jason.encode!(%{status: "ok", service: "payment_processor"}))
  end

  # Process payment
  post "/payments" do
    with {:ok, correlation_id} <- get_correlation_id(conn),
         {:ok, amount} <- get_amount(conn) do
      
      requested_at = DateTime.utc_now()
      
      case DistributedCoordinatorClient.enqueue_payment(correlation_id, amount, requested_at) do
        {:ok, :queued} ->
          send_resp(conn, 200, Jason.encode!(%{status: "success"}))
        {:error, reason} ->
          Logger.warning("Payment enqueueing failed: #{inspect(reason)}")
          send_resp(conn, 500, Jason.encode!(%{error: "Internal server error"}))
      end
    else
      {:error, :missing_correlation_id} ->
        send_resp(conn, 400, Jason.encode!(%{error: "Missing correlationId"}))
      {:error, :missing_amount} ->
        send_resp(conn, 400, Jason.encode!(%{error: "Missing amount"}))
      {:error, :invalid_correlation_id} ->
        send_resp(conn, 400, Jason.encode!(%{error: "Invalid correlationId format"}))
      {:error, :invalid_amount} ->
        send_resp(conn, 400, Jason.encode!(%{error: "Invalid amount"}))
    end
  end

  # Get payments summary
  get "/payments-summary" do
    query_params = Plug.Conn.fetch_query_params(conn).query_params
    from_timestamp = parse_optional_timestamp(Map.get(query_params, "from"))
    to_timestamp = parse_optional_timestamp(Map.get(query_params, "to"))

    case {from_timestamp, to_timestamp} do
      {{:ok, from_ts}, {:ok, to_ts}} ->
        case DistributedCoordinatorClient.get_payments_summary(from_ts, to_ts) do
          {:ok, summary} ->
            send_resp(conn, 200, Jason.encode!(summary))
          {:error, reason} ->
            Logger.warning("Summary request failed: #{inspect(reason)}")
            send_resp(conn, 500, Jason.encode!(%{error: "Internal server error"}))
        end
        
      {{:error, _}, _} ->
        send_resp(conn, 400, Jason.encode!(%{error: "Invalid 'from' timestamp format"}))
        
      {_, {:error, _}} ->
        send_resp(conn, 400, Jason.encode!(%{error: "Invalid 'to' timestamp format"}))
    end
  end

  # Catch-all for unmatched routes
  match _ do
    send_resp(conn, 404, Jason.encode!(%{error: "Not found"}))
  end

  # Helper functions
  defp get_correlation_id(%{body_params: %{"correlationId" => correlation_id}}) when is_binary(correlation_id) do
    case validate_uuid(correlation_id) do
      {:ok, _} -> {:ok, correlation_id}
      :error -> {:error, :invalid_correlation_id}
    end
  end
  
  defp get_correlation_id(_), do: {:error, :missing_correlation_id}

  defp get_amount(%{body_params: %{"amount" => amount}}) when is_number(amount) and amount > 0 do
    {:ok, Decimal.from_float(amount)}
  end
  
  defp get_amount(%{body_params: %{"amount" => amount}}) when is_binary(amount) do
    case Decimal.parse(amount) do
      {decimal, ""} when not is_nil(decimal) ->
        if Decimal.positive?(decimal), do: {:ok, decimal}, else: {:error, :invalid_amount}
      _ ->
        {:error, :invalid_amount}
    end
  end
  
  defp get_amount(_), do: {:error, :missing_amount}

  defp validate_uuid(correlation_id) do
    # Simple UUID validation using regex (same as Phoenix controller)
    uuid_regex = ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    if Regex.match?(uuid_regex, correlation_id) do
      {:ok, correlation_id}
    else
      :error
    end
  end

  defp parse_optional_timestamp(nil), do: {:ok, nil}
  
  defp parse_optional_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _} -> {:ok, datetime}
      {:error, _} -> {:error, :invalid_timestamp}
    end
  end
  
  defp parse_optional_timestamp(_), do: {:error, :invalid_timestamp}

  # Server startup functions  
  def child_spec(opts) do
    port = Keyword.get(opts, :port, 9999)
    
    Bandit.child_spec(
      plug: __MODULE__,
      scheme: :http,
      port: port
    )
  end
end