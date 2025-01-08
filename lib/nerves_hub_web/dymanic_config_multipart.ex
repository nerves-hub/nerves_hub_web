defmodule NervesHubWeb.DymanicConfigMultipart do
  @moduledoc """
  A wrapper around `Plug.Parsers.MULTIPART` which allows for the `:length` opt (max file size)
  to be set during runtime.

  This can later be expanded to allow for different file size limits based on the organization.

  Thank you to https://hexdocs.pm/plug/Plug.Parsers.MULTIPART.html#module-dynamic-configuration
  for the inspiration.
  """

  @multipart Plug.Parsers.MULTIPART

  def init(opts) do
    opts
  end

  def parse(conn, "multipart", subtype, headers, opts) do
    opts = @multipart.init([length: max_file_size()] ++ opts)
    @multipart.parse(conn, "multipart", subtype, headers, opts)
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end

  defp max_file_size() do
    Application.get_env(:nerves_hub, NervesHub.Firmwares.Upload, [])[:max_size]
  end
end
