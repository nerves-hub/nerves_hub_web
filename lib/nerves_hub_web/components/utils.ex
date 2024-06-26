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
end
