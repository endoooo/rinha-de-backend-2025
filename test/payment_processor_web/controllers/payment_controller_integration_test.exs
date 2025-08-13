defmodule PaymentProcessorWeb.PaymentControllerIntegrationTest do
  use PaymentProcessorWeb.ConnCase
  
  # Note: These tests expect coordinator to be unavailable during test runs
  # They verify that the API handles coordinator failures gracefully
  
  test "POST /payments without coordinator returns service unavailable", %{conn: conn} do
    payment_params = %{
      "correlationId" => "550e8400-e29b-41d4-a716-446655440000",
      "amount" => 100.50
    }
    
    conn = post(conn, ~p"/payments", payment_params)
    
    assert json_response(conn, 503) == %{"error" => "Payment processing service unavailable"}
  end
  
  test "GET /payments-summary without coordinator returns service unavailable", %{conn: conn} do
    conn = get(conn, ~p"/payments-summary")
    
    assert json_response(conn, 503) == %{"error" => "Summary service unavailable"}
  end
  
  test "POST /payments with invalid UUID should return bad request", %{conn: conn} do
    payment_params = %{
      "correlationId" => "invalid-uuid",
      "amount" => 100.50
    }
    
    conn = post(conn, ~p"/payments", payment_params)
    assert json_response(conn, 400) == %{"error" => "Invalid correlation ID format"}
  end
  
  test "POST /payments with invalid amount should return bad request", %{conn: conn} do
    payment_params = %{
      "correlationId" => "550e8400-e29b-41d4-a716-446655440002",
      "amount" => -10
    }
    
    conn = post(conn, ~p"/payments", payment_params)
    assert json_response(conn, 400) == %{"error" => "Invalid amount"}
  end

  test "POST /payments with missing fields should return bad request", %{conn: conn} do
    conn = post(conn, ~p"/payments", %{})
    assert json_response(conn, 400) == %{"error" => "Missing required fields: correlationId, amount"}
  end
end