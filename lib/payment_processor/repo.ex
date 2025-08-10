defmodule PaymentProcessor.Repo do
  use Ecto.Repo,
    otp_app: :payment_processor,
    adapter: Ecto.Adapters.Postgres
end
