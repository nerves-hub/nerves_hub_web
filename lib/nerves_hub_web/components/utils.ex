defmodule NervesHubWeb.Components.Utils do
  use NervesHubWeb, :component

  alias NervesHub.Accounts.OrgUser
  alias Phoenix.HTML.FormField

  def role_options() do
    for {key, value} <- Ecto.Enum.mappings(OrgUser, :role),
        key in [:admin, :manage, :view],
        do: {String.capitalize(value), key}
  end

  @doc """
  A measurement period in seconds as a compact human string: "90s", "30m",
  "6h", "1d".
  """
  def format_period(seconds) when seconds < 60, do: "#{seconds}s"
  def format_period(seconds) when rem(seconds, 86_400) == 0, do: "#{div(seconds, 86_400)}d"
  def format_period(seconds) when rem(seconds, 3600) == 0, do: "#{div(seconds, 3600)}h"
  def format_period(seconds) when rem(seconds, 60) == 0, do: "#{div(seconds, 60)}m"
  def format_period(seconds), do: "#{div(seconds, 60)}m #{rem(seconds, 60)}s"

  def format_serial(big_long_integer) when is_integer(big_long_integer) do
    big_long_integer
    |> Integer.to_string(16)
    |> to_charlist()
    |> Enum.chunk_every(2)
    |> Enum.join(":")
  end

  def format_serial(serial_str) when is_binary(serial_str) do
    String.to_integer(serial_str)
    |> format_serial()
  end

  def cpu_temp_to_status(temp) do
    case temp do
      temp when temp < 60 -> ""
      temp when temp < 90 -> "warn"
      _ -> "danger"
    end
  end

  def usage_percent_to_status(usage) do
    case usage do
      usage when usage < 80 -> ""
      usage when usage < 90 -> "warn"
      _ -> "danger"
    end
  end

  def disk_usage(%{"disk_available_kb" => available, "disk_total_kb" => total, "disk_used_percentage" => percentage}) do
    usage = (total - available) / 1000

    "#{Sizeable.filesize(usage * 1024)} of #{Sizeable.filesize(available * 1024)} (#{round(percentage)}%)"
  end

  def tags_to_string(%FormField{} = field) do
    tags_to_string(field.value)
  end

  def tags_to_string(%{tags: tags}), do: tags_to_string(tags)
  def tags_to_string(tags) when is_list(tags), do: Enum.join(tags, ", ")
  def tags_to_string(tags), do: tags
end
