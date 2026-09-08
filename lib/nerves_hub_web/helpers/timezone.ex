defmodule NervesHubWeb.Helpers.Timezone do
  @moduledoc """
  Resolves the IANA time zone name used to render timestamps for a viewer.

  The name arrives from the browser (`Intl.DateTimeFormat().resolvedOptions().timeZone`),
  either as a LiveView connect param or as the cookie `NervesHubWeb.Plugs.Timezone`
  copies into the session. Both are attacker-controlled, so every name is checked
  against the time zone database before it reaches `Calendar.strftime/2` or a
  ClickHouse query, and anything unrecognised falls back to UTC.
  """

  @default "Etc/UTC"

  # Comfortably longer than the longest name in the tz database (32 bytes), without
  # letting a hostile cookie hand us a novel to look up.
  @max_length 64

  @doc """
  The zone used when the browser hasn't told us one, or told us one we don't know.
  """
  @spec default() :: String.t()
  def default(), do: @default

  @doc """
  Returns `{:ok, time_zone}` when the name is one the time zone database knows.
  """
  @spec validate(term()) :: {:ok, String.t()} | :error
  def validate(time_zone) when is_binary(time_zone) and byte_size(time_zone) <= @max_length do
    case DateTime.now(time_zone) do
      {:ok, _now} -> {:ok, time_zone}
      {:error, _reason} -> :error
    end
  end

  def validate(_time_zone), do: :error

  @doc """
  Returns the first recognised time zone name, or UTC when none of them are.

  Callers pass their preference order, most trusted first.
  """
  @spec resolve([term()] | term()) :: String.t()
  def resolve(candidates) when is_list(candidates) do
    Enum.find_value(candidates, @default, fn candidate ->
      case validate(candidate) do
        {:ok, time_zone} -> time_zone
        :error -> nil
      end
    end)
  end

  def resolve(candidate), do: resolve([candidate])
end
