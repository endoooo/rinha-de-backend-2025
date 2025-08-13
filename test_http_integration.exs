#!/usr/bin/env elixir

# Quick integration test for HTTP coordinator architecture
Mix.install([
  {:finch, "~> 0.16"},
  {:jason, "~> 1.4"}
])

defmodule HTTPIntegrationTest do
  def run do
    IO.puts("=== HTTP Coordinator Integration Test ===")
    
    # Start Finch for HTTP requests
    {:ok, _} = Finch.start_link(name: TestFinch)
    
    coordinator_url = System.get_env("COORDINATOR_URL", "http://localhost:8080")
    IO.puts("Testing coordinator at: #{coordinator_url}")
    
    # Test 1: Health check
    IO.puts("\n1. Testing coordinator health...")
    case test_health(coordinator_url) do
      :ok -> IO.puts("✅ Health check passed")
      :error -> IO.puts("❌ Health check failed")
    end
    
    # Test 2: Enqueue payment
    IO.puts("\n2. Testing payment enqueue...")
    correlation_id = "test-#{:os.system_time(:microsecond)}"
    case test_enqueue_payment(coordinator_url, correlation_id) do
      :ok -> IO.puts("✅ Payment enqueue passed")
      :error -> IO.puts("❌ Payment enqueue failed")
    end
    
    # Test 3: Get summary
    IO.puts("\n3. Testing summary retrieval...")
    case test_summary(coordinator_url) do
      :ok -> IO.puts("✅ Summary retrieval passed")
      :error -> IO.puts("❌ Summary retrieval failed")
    end
    
    # Test 4: Queue status
    IO.puts("\n4. Testing queue status...")
    case test_queue_status(coordinator_url) do
      :ok -> IO.puts("✅ Queue status passed")
      :error -> IO.puts("❌ Queue status failed")
    end
    
    IO.puts("\n=== Integration Test Complete ===")
  end
  
  defp test_health(url) do
    case make_request(:get, "#{url}/health") do
      {:ok, 200, body} ->
        case Jason.decode(body) do
          {:ok, %{"status" => "ok"}} -> :ok
          _ -> :error
        end
      _ -> :error
    end
  end
  
  defp test_enqueue_payment(url, correlation_id) do
    payload = %{
      "correlationId" => correlation_id,
      "amount" => 123.45
    }
    
    case make_request(:post, "#{url}/enqueue-payment", Jason.encode!(payload)) do
      {:ok, 201, body} ->
        case Jason.decode(body) do
          {:ok, %{"status" => "queued"}} -> :ok
          _ -> :error
        end
      _ -> :error
    end
  end
  
  defp test_summary(url) do
    case make_request(:get, "#{url}/payments-summary") do
      {:ok, 200, body} ->
        case Jason.decode(body) do
          {:ok, %{"default" => _, "fallback" => _}} -> :ok
          _ -> :error
        end
      _ -> :error
    end
  end
  
  defp test_queue_status(url) do
    case make_request(:get, "#{url}/queue-status") do
      {:ok, 200, body} ->
        case Jason.decode(body) do
          {:ok, %{"queue_size" => _, "processing" => _}} -> :ok
          _ -> :error
        end
      _ -> :error
    end
  end
  
  defp make_request(method, url, body \\ "") do
    headers = if body != "", do: [{"content-type", "application/json"}], else: []
    request = Finch.build(method, url, headers, body)
    
    case Finch.request(request, TestFinch, receive_timeout: 5000) do
      {:ok, %{status: status, body: response_body}} ->
        {:ok, status, response_body}
      {:error, _reason} ->
        :error
    end
  end
end

HTTPIntegrationTest.run()