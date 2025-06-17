defmodule NervesHubWeb.DynamicConfigMultipart do
  @moduledoc """
  A wrapper around `Plug.Parsers.MULTIPART` which allows for the `:length` opt (max file size)
  to be set during runtime.

  This also restricts large file uploads to the firmware upload api route.

  This can later be expanded to allow for different file size limits based on the organization.

  Thank you to https://hexdocs.pm/plug/Plug.Parsers.MULTIPART.html#module-dynamic-configuration
  for the inspiration.
  """

  @multipart Plug.Parsers.MULTIPART

  def init(opts) do
    opts
    |> Keyword.put_new(:max_default_size, 1_000_000)
    |> Keyword.put_new_lazy(:max_firmware_size, fn ->
        Application.get_env(:nerves_hub, NervesHub.Firmwares.Upload, [])[:max_size]
    end)
  end

  def parse(conn, "multipart", subtype, headers, opts) do
    opts = @multipart.init([length: max_file_size(conn, opts)] ++ opts)
    @multipart.parse(conn, "multipart", subtype, headers, opts)
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end

  defp max_file_size(conn, opts) do
    case conn.path_info do
      ["api", "orgs", _org_name, "products", _product_name, "firmwares"] ->
        Keyword.fetch!(opts, :max_firmware_size)

      _ ->
        Keyword.fetch!(opts, :max_default_size)
    end
  end
end
