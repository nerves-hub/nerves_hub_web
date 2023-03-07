defmodule NervesHubWeb.OrgCertificateView do
  use NervesHubWeb, :view

  alias NervesHubWeb.LayoutView.DateTimeFormat, as: DateTimeFormat

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

  def check_expiration_help_text() do
    """
    By default, the time validity of CA certificates is unchecked. You can
    toggle this to check expiration to prevent device certificates
    from being created from an expired signing CA certificate.
    """
  end
end
