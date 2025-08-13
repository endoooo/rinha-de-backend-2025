defmodule QueueCoordinator.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # HTTP client for making requests to payment processors
      {Finch, name: QueueCoordinator.HTTPClient},
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
end
