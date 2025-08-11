defmodule PaymentProcessor.ProcessorClient do
  @moduledoc """
  HTTP client for communicating with payment processors using Finch.
  Handles health checks and payment processing requests.
  """

  @default_processor_url "http://payment-processor-default:8080"
  @fallback_processor_url "http://payment-processor-fallback:8080"

  def child_spec(_opts) do
    Finch.child_spec(name: __MODULE__)
  end

  def health_check(:default) do
    make_request(:get, "#{@default_processor_url}/payments/service-health")
  end

  def health_check(:fallback) do
    make_request(:get, "#{@fallback_processor_url}/payments/service-health")
  end

  def process_payment(processor_type, correlation_id, amount, requested_at) do
    url = processor_url(processor_type)

    body =
      Jason.encode!(%{
        correlationId: correlation_id,
        amount: amount,
        requestedAt: requested_at |> DateTime.to_iso8601()
      })

    make_request(:post, "#{url}/payments", body, [{"content-type", "application/json"}])
  end

  defp processor_url(:default), do: @default_processor_url
  defp processor_url(:fallback), do: @fallback_processor_url

  defp make_request(method, url, body \\ "", headers \\ []) do
    request = Finch.build(method, url, headers, body)

    case Finch.request(request, __MODULE__, receive_timeout: 5000) do
      {:ok, %Finch.Response{status: status} = response} when status in 200..299 ->
        {:ok, response}

      {:ok, %Finch.Response{} = response} ->
        {:error, {:http_error, response.status, response.body}}

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end
end
