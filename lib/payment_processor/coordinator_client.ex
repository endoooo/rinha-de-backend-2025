defmodule PaymentProcessor.CoordinatorClient do
  @moduledoc """
  HTTP client for communicating with the queue coordinator service.
  """
  require Logger

  defp coordinator_url do
    System.get_env("COORDINATOR_URL", "http://localhost:8080")
  end

  def enqueue_payment(correlation_id, amount, requested_at) do
    body = Jason.encode!(%{
      correlationId: correlation_id,
      amount: amount,
      requestedAt: DateTime.to_iso8601(requested_at)
    })

    headers = [{"content-type", "application/json"}]
    request = Finch.build(:post, "#{coordinator_url()}/enqueue-payment", headers, body)

    case Finch.request(request, PaymentProcessor.ProcessorClient, receive_timeout: 2_000) do
      {:ok, %Finch.Response{status: 201}} ->
        {:ok, :queued}
      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.warning("Coordinator returned error: #{status}, #{body}")
        {:error, {:coordinator_error, status}}
      {:error, reason} ->
        Logger.debug("Failed to communicate with coordinator: #{inspect(reason)}")
        {:error, {:network_error, reason}}
    end
  end

  def get_payments_summary(from_timestamp \\ nil, to_timestamp \\ nil) do
    query_params = build_query_params(from_timestamp, to_timestamp)
    url = "#{coordinator_url()}/payments-summary#{query_params}"
    request = Finch.build(:get, url)

    case Finch.request(request, PaymentProcessor.ProcessorClient, receive_timeout: 5_000) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, summary} -> {:ok, summary}
          {:error, _} -> {:error, :invalid_response}
        end
      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.warning("Coordinator summary error: #{status}, #{body}")
        {:error, {:coordinator_error, status}}
      {:error, reason} ->
        Logger.debug("Failed to get summary from coordinator: #{inspect(reason)}")
        {:error, {:network_error, reason}}
    end
  end

  def get_queue_status do
    request = Finch.build(:get, "#{coordinator_url()}/queue-status")

    case Finch.request(request, PaymentProcessor.ProcessorClient, receive_timeout: 5_000) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, status} -> {:ok, status}
          {:error, _} -> {:error, :invalid_response}
        end
      {:ok, %Finch.Response{status: status}} ->
        {:error, {:coordinator_error, status}}
      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  defp build_query_params(nil, nil), do: ""
  defp build_query_params(from_ts, nil), do: "?from=#{DateTime.to_iso8601(from_ts)}"
  defp build_query_params(nil, to_ts), do: "?to=#{DateTime.to_iso8601(to_ts)}"
  defp build_query_params(from_ts, to_ts), do: "?from=#{DateTime.to_iso8601(from_ts)}&to=#{DateTime.to_iso8601(to_ts)}"
end