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

    config = Application.get_env(:nerves_hub, __MODULE__)

    result <= config[:limit]
  end

  @doc false
  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end

  @impl true
  def init(_) do
    state = %{
      ets_key: :nerves_hub_rate_limit
    }

    _ =
      :ets.new(state.ets_key, [
        :named_table,
        :set,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, _} = :timer.send_interval(10_000, :prune)

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
