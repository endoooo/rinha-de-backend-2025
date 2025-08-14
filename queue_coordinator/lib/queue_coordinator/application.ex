defmodule QueueCoordinator.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Configure distributed Erlang node
    setup_distributed_node()
    
    children = [
      # HTTP client for making requests to payment processors with optimized pools
      {Finch, name: QueueCoordinator.HTTPClient, pools: build_finch_pools()},
      # Task supervisor for concurrent payment processing
      {Task.Supervisor, name: QueueCoordinator.TaskSupervisor},
      # Processor health monitoring for smart routing
      QueueCoordinator.ProcessorHealthMonitor,
      # Queue storage and processing
      QueueCoordinator.QueueManager,
      QueueCoordinator.Storage,
      # HTTP server (backup for health checks)
      {Plug.Cowboy, scheme: :http, plug: QueueCoordinator.Router, options: [port: 8080]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: QueueCoordinator.Supervisor]
    
    Supervisor.start_link(children, opts)
  end
  
  defp setup_distributed_node do
    # Start distributed Erlang if not already started
    case Node.start(:"coordinator@coordinator") do
      {:ok, _} -> 
        require Logger
        Logger.info("Started distributed node: #{Node.self()}")
      {:error, {:already_started, _}} -> 
        require Logger
        Logger.info("Distributed node already running: #{Node.self()}")
      {:error, reason} ->
        require Logger
        Logger.warning("Failed to start distributed node: #{inspect(reason)}")
    end
    
    # Set up node cookie for cluster security
    cookie = System.get_env("ERL_COOKIE", "rinha_cluster_cookie")
    Node.set_cookie(String.to_atom(cookie))
  end
  
  defp build_finch_pools do
    # Configure pools for both payment processors - larger pools to handle both payments and health checks
    %{
      "http://payment-processor-default:8080" => [
        size: 20,  # Larger pool to handle both payments and health checks
        count: 1,  # Single pool - simpler management
        conn_opts: [
          transport_opts: [
            inet6: false,
            nodelay: true,
            keepalive: true
          ]
        ],
        conn_max_idle_time: 60_000,  # Longer idle time
        pool_max_idle_time: 300_000  # Pool stays alive longer
      ],
      "http://payment-processor-fallback:8080" => [
        size: 20,
        count: 1,
        conn_opts: [
          transport_opts: [
            inet6: false,
            nodelay: true,
            keepalive: true
          ]
        ],
        conn_max_idle_time: 60_000,
        pool_max_idle_time: 300_000
      ]
    }
  end
end
