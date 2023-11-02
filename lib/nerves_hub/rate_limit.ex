defmodule NervesHub.RateLimit do
  @moduledoc """
  Rate Limit devices connecting to the server
  """

  use GenServer

  @doc """
  Increment and check the rate limit

  Return `true` if the request was under the rate limit
  """
  @spec increment() :: boolean()
  def increment() do
    bucket_key =
      DateTime.utc_now()
      |> DateTime.to_unix()

    result = :ets.update_counter(:nerves_hub_rate_limit, bucket_key, 1, {bucket_key, 0})

    result < :persistent_term.get(__MODULE__)
  end

  @doc false
  def start_link(opts) do
    limit = opts[:limit] || raise ArgumentError, ":limit is required"

    GenServer.start_link(__MODULE__, limit)
  end

  @impl true
  def init(limit) do
    :persistent_term.put(__MODULE__, limit)

    state = %{
      ets_key: :nerves_hub_rate_limit
    }

    :ets.new(state.ets_key, [
      :named_table,
      :set,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    :timer.send_interval(10_000, :prune)

    {:ok, state}
  end

  @impl true
  def handle_info(:prune, state) do
    minute_ago =
      DateTime.utc_now()
      |> DateTime.add(-60, :second)
      |> DateTime.to_unix()

    deleted =
      :ets.select_delete(state.ets_key, [
        {{:"$1", :_}, [{:<, :"$1", minute_ago}], [true]}
      ])

    :telemetry.execute([:nerves_hub, :rate_limit, :pruned], %{count: deleted})

    {:noreply, state}
  end
end
