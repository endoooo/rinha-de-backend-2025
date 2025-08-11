import Config

# Do not print debug messages in production
config :logger, level: :info

# Production-specific Phoenix endpoint config
config :payment_processor, PaymentProcessorWeb.Endpoint, http: [ip: {0, 0, 0, 0}, port: 9999]

# Database connection pool optimization
config :payment_processor, PaymentProcessor.Repo,
  pool_size: 15,
  queue_target: 50,
  queue_interval: 1000

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
