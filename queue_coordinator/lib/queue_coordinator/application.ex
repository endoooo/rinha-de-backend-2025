defmodule QueueCoordinator.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # HTTP client for making requests to payment processors with optimized pools
      {Finch, name: QueueCoordinator.HTTPClient, pools: build_finch_pools()},
      # Task supervisor for concurrent payment processing
      {Task.Supervisor, name: QueueCoordinator.TaskSupervisor},
      # Queue storage and processing
      QueueCoordinator.QueueManager,
      QueueCoordinator.Storage,
      # HTTP server
      {Plug.Cowboy, scheme: :http, plug: QueueCoordinator.Router, options: [port: 8080]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: QueueCoordinator.Supervisor]
    Supervisor.start_link(children, opts)
  end
  
  defp build_finch_pools do
    # Configure pools for both payment processors
    %{
      "http://payment-processor-default:8080" => [
        size: 10,  # 10 connections per pool
        count: 2,  # 2 pools = 20 total connections
        conn_opts: [
          transport_opts: [
            inet6: false,
            nodelay: true,
            keepalive: true
          ]
        ],
        conn_max_idle_time: 30_000
      ],
      "http://payment-processor-fallback:8080" => [
        size: 10,
        count: 2,
        conn_opts: [
          transport_opts: [
            inet6: false,
            nodelay: true,
            keepalive: true
          ]
        ],
        conn_max_idle_time: 30_000
      ]
    }
  end
end
