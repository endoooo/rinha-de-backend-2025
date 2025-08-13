import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :payment_processor, PaymentProcessorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "VE9qbrFHcgaoDdw+5A4kNWam1M/urLBZD0xPgXIZ2pAdbS+TSdt5verWxa4h9gGm",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
