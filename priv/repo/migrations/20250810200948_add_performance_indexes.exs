defmodule PaymentProcessor.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def change do
    # Add composite index for payments summary queries
    create index(:payments, [:processor_used, :processed_at])
    create index(:payments, [:status, :processed_at])
    
    # Optimize correlation_id lookups (already exists but ensure it's there)
    create_if_not_exists unique_index(:payments, [:correlation_id])
  end
end
