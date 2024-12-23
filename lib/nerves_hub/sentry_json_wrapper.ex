defmodule NervesHub.SentryJsonWrapper do
  # Sentry tries to validate the JSON library configured, but the builtin
  # JSON library doesn't define `encode`, only `encode!`.
  # This little wrapper fixes that, until Sentry is updated to support `encode!`, or
  # `JSON` supports `encode`.
  # https://github.com/getsentry/sentry-elixir/blob/master/lib/sentry/config.ex#L696-L714

  def encode(data) do
    try do
      {:ok, JSON.encode!(data)}
    rescue
      e ->
        {:error, e}
    end
  end

  def decode(data) do
    JSON.decode(data)
  end
end
