defmodule PaymentProcessor.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Configure distributed Erlang node
    setup_distributed_node()
    
    # Build Finch pools dynamically at runtime  
    finch_pools = build_finch_pools()
    
    # Log coordinator configuration
    require Logger
    Logger.info("Starting API instance #{node_name()} with coordinator: #{coordinator_node()}")
    
    children = [
      # HTTP client for coordinator communication (backup)
      {Finch, name: PaymentProcessor.ProcessorClient, pools: finch_pools},
      # Health check for coordinator connectivity  
      PaymentProcessor.CoordinatorHealthCheck,
      # Lightweight HTTP server (replaces Phoenix)
      {PaymentProcessor.HTTPServer, port: get_port()}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PaymentProcessor.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp get_port do
    System.get_env("PORT", "9999") |> String.to_integer()
  end
  
  defp setup_distributed_node do
    # Start distributed Erlang node
    case Node.start(node_name()) do
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
    
    # Attempt to connect to coordinator
    connect_to_coordinator()
  end
  
  defp connect_to_coordinator do
    coordinator = coordinator_node()
    case Node.connect(coordinator) do
      true ->
        require Logger
        Logger.info("Connected to coordinator node: #{coordinator}")
      false ->
        require Logger
        Logger.warning("Failed to connect to coordinator node: #{coordinator}")
        # Retry connection after a delay
        Process.send_after(self(), :retry_coordinator_connection, 5000)
    end
  end
  
  defp node_name do
    hostname = System.get_env("NODE_NAME", "api")
    String.to_atom("#{hostname}@#{hostname}")
  end
  
  defp coordinator_node do
    String.to_atom("queue_coordinator@coordinator")
  end

  defp coordinator_url do
    System.get_env("COORDINATOR_URL", "http://localhost:8080")
  end

  defp build_finch_pools do
    coordinator_url = coordinator_url()
    
    %{
      coordinator_url => [
        size: 20,
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
