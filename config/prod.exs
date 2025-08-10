import Config

# Do not print debug messages in production
config :logger, level: :info

# Production-specific Phoenix endpoint config
config :payment_processor, PaymentProcessorWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 9999],
  cache_static_manifest: "priv/static/cache_manifest.json"

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
