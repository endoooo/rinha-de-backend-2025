defmodule PaymentProcessor.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PaymentProcessorWeb.Telemetry,
      PaymentProcessor.Repo,
      {Finch, name: PaymentProcessor.ProcessorClient},
      PaymentProcessor.ProcessorMonitor,
      {DNSCluster, query: Application.get_env(:payment_processor, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PaymentProcessor.PubSub},
      # Start a worker by calling: PaymentProcessor.Worker.start_link(arg)
      # {PaymentProcessor.Worker, arg},
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
end
