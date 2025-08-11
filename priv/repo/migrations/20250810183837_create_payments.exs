defmodule PaymentProcessor.Repo.Migrations.CreatePayments do
  use Ecto.Migration

  def change do
    create table(:payments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :correlation_id, :uuid, null: false
      add :amount, :decimal, precision: 15, scale: 2, null: false
      add :processor_used, :string, null: false
      add :status, :string, null: false
      add :processor_response, :map
      add :processed_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:payments, [:correlation_id])
    create index(:payments, [:processed_at])

    # Add composite index for payments summary queries
    create index(:payments, [:processor_used, :processed_at])
    create index(:payments, [:status, :processed_at])
  end
end
