defmodule QueueCoordinator.RouterTest do
  use ExUnit.Case
  use Plug.Test

  alias QueueCoordinator.Router

  @opts Router.init([])

  test "health check returns ok" do
    conn = conn(:get, "/health")
    conn = Router.call(conn, @opts)

    assert conn.state == :sent
    assert conn.status == 200
    
    response = Jason.decode!(conn.resp_body)
    assert response["status"] == "ok"
    assert response["service"] == "queue_coordinator"
  end

  test "enqueue payment with valid data" do
    payment_data = %{
      "correlationId" => "550e8400-e29b-41d4-a716-446655440000",
      "amount" => 100.50
    }

    conn = conn(:post, "/enqueue-payment", Jason.encode!(payment_data))
    conn = put_req_header(conn, "content-type", "application/json")
    conn = Router.call(conn, @opts)

    assert conn.status == 201
    response = Jason.decode!(conn.resp_body)
    assert response["status"] == "queued"
  end

  test "enqueue payment with invalid UUID still accepts (validates during processing)" do
    payment_data = %{
      "correlationId" => "invalid-uuid",
      "amount" => 100.50
    }

    conn = conn(:post, "/enqueue-payment", Jason.encode!(payment_data))
    conn = put_req_header(conn, "content-type", "application/json")
    conn = Router.call(conn, @opts)

    # Coordinator accepts all requests and validates during processing
    assert conn.status == 201
    response = Jason.decode!(conn.resp_body)
    assert response["status"] == "queued"
  end

  test "enqueue payment with missing fields" do
    payment_data = %{"amount" => 100.50}

    conn = conn(:post, "/enqueue-payment", Jason.encode!(payment_data))
    conn = put_req_header(conn, "content-type", "application/json")
    conn = Router.call(conn, @opts)

    assert conn.status == 400
    response = Jason.decode!(conn.resp_body)
    assert response["error"] == "Missing required fields: correlationId, amount"
  end

  test "get queue status" do
    conn = conn(:get, "/queue-status")
    conn = Router.call(conn, @opts)

    assert conn.status == 200
    response = Jason.decode!(conn.resp_body)
    assert Map.has_key?(response, "queue_size")
    assert Map.has_key?(response, "processing")
  end

  test "get payments summary" do
    conn = conn(:get, "/payments-summary")
    conn = Router.call(conn, @opts)

    assert conn.status == 200
    response = Jason.decode!(conn.resp_body)
    assert Map.has_key?(response, "default")
    assert Map.has_key?(response, "fallback")
  end

  test "get payments summary with timestamps" do
    from_ts = "2025-01-01T00:00:00Z"
    to_ts = "2025-12-31T23:59:59Z"
    
    conn = conn(:get, "/payments-summary?from=#{from_ts}&to=#{to_ts}")
    conn = Router.call(conn, @opts)

    assert conn.status == 200
    response = Jason.decode!(conn.resp_body)
    assert Map.has_key?(response, "default")
    assert Map.has_key?(response, "fallback")
  end

  test "get payments summary with invalid timestamp" do
    conn = conn(:get, "/payments-summary?from=invalid-timestamp")
    conn = Router.call(conn, @opts)

    assert conn.status == 400
    response = Jason.decode!(conn.resp_body)
    assert response["error"] == "Invalid 'from' timestamp format"
  end

  test "404 for unknown routes" do
    conn = conn(:get, "/unknown-route")
    conn = Router.call(conn, @opts)

    assert conn.status == 404
    response = Jason.decode!(conn.resp_body)
    assert response["error"] == "Not found"
  end
end