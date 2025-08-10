defmodule PaymentProcessor.Payments do
  import Ecto.Query, warn: false
  alias PaymentProcessor.Repo
  alias PaymentProcessor.Payments.Payment

  def create_payment(attrs \\ %{}) do
    %Payment{}
    |> Payment.changeset(attrs)
    |> Repo.insert()
  end

  def get_payment_by_correlation_id(correlation_id) do
    Repo.get_by(Payment, correlation_id: correlation_id)
  end

  def get_payments_summary(from_timestamp \\ nil) do
    query = from p in Payment

    query = if from_timestamp do
      from p in query, where: p.processed_at >= ^from_timestamp
    else
      query
    end

    results = from(p in query,
      group_by: p.processor_used,
      select: {
        p.processor_used,
        count(p.id),
        sum(p.amount)
      }
    ) |> Repo.all()

    %{
      default: extract_processor_stats(results, "default"),
      fallback: extract_processor_stats(results, "fallback")
    }
  end

  defp extract_processor_stats(results, processor_type) do
    case Enum.find(results, fn {proc, _count, _sum} -> proc == processor_type end) do
      {_processor, count, sum} -> %{count: count, total_amount: sum || Decimal.new(0)}
      nil -> %{count: 0, total_amount: Decimal.new(0)}
    end
  end
end