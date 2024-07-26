defmodule NervesHubWeb.Components.Utils do
  use NervesHubWeb, :component

  alias NervesHub.Accounts.OrgUser

  def role_options() do
    for {key, value} <- Ecto.Enum.mappings(OrgUser, :role),
        key in [:admin, :manage, :view],
        do: {String.capitalize(value), key}
  end

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

  def memory_to_status(percent) do
    case percent do
      _ when percent > 80 -> "warn"
      _ when percent > 90 -> "danger"
      _ -> ""
    end
  end
end
