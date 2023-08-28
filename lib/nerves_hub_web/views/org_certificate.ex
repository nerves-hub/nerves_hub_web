defmodule NervesHubWeb.OrgCertificateView do
  use NervesHubWeb, :view

  alias NervesHubWeb.LayoutView.DateTimeFormat

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

  def ski_only_help_text() do
    """
    This is a special case for creating a CA certificate when only the
    Subject Key Identifier (SKI) is known. This is for cases where the
    device certificate is signed by an intermediate CA certificate and
    the full chain is not known. If this intermediate signer CA is presented
    in the chain, this enables NervesHub to still validate the device
    certificate. This certificate will not support Just-In-Time Provisioning
    """
  end
end
