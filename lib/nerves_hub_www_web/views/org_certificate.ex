defmodule NervesHubWWWWeb.OrgCertificateView do
  use NervesHubWWWWeb, :view

  alias NervesHubWWWWeb.LayoutView.DateTimeFormat, as: DateTimeFormat

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
