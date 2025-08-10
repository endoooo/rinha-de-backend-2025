defmodule PaymentProcessor.Payments.Payment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "payments" do
    field :correlation_id, Ecto.UUID
    field :amount, :decimal
    field :processor_used, :string
    field :status, :string
    field :processor_response, :map
    field :processed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(payment, attrs) do
    payment
    |> cast(attrs, [:correlation_id, :amount, :processor_used, :status, :processor_response, :processed_at])
    |> validate_required([:correlation_id, :amount, :processor_used, :status, :processed_at])
    |> validate_number(:amount, greater_than: 0)
    |> validate_inclusion(:processor_used, ["default", "fallback", "pending"])
    |> validate_inclusion(:status, ["success", "failed", "pending"])
    |> unique_constraint(:correlation_id)
  end
end