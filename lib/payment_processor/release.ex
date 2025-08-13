defmodule PaymentProcessor.Release do
  @moduledoc """
  Used for executing release tasks when run in production without Mix
  installed. No database migrations needed with ETS-based storage.
  """
  @app :payment_processor

  def migrate do
    # No database migrations needed with ETS storage
    load_app()
    :ok
  end

  def rollback(_repo, _version) do
    # No database rollbacks needed with ETS storage
    load_app()
    :ok
  end

  defp load_app do
    Application.load(@app)
  end
end