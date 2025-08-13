defmodule PaymentProcessor.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Build Finch pools dynamically at runtime
    finch_pools = build_finch_pools()
    
    # Log coordinator configuration
    require Logger
    Logger.info("Starting API instance with coordinator URL: #{coordinator_url()}")
    
    children = [
      PaymentProcessorWeb.Telemetry,
      # HTTP client for coordinator communication
      {Finch, name: PaymentProcessor.ProcessorClient, pools: finch_pools},
      # Health check for coordinator connectivity
      PaymentProcessor.CoordinatorHealthCheck,
      {DNSCluster, query: Application.get_env(:payment_processor, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PaymentProcessor.PubSub},
      # Start to serve requests, typically the last entry
      PaymentProcessorWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PaymentProcessor.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PaymentProcessorWeb.Endpoint.config_change(changed, removed)
    :ok
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
