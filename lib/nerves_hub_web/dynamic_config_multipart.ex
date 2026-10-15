defmodule NervesHubWeb.DynamicConfigMultipart do
  @moduledoc """
  A wrapper around `Plug.Parsers.MULTIPART` which allows for the `:length` opt (max file size)
  to be set during runtime.

  This also restricts large file uploads to the firmware and archive upload api routes.

  This can later be expanded to allow for different file size limits based on the organization.

  Thank you to https://hexdocs.pm/plug/Plug.Parsers.MULTIPART.html#module-dynamic-configuration
  for the inspiration.
  """
  @behaviour Plug.Parsers

  alias NervesHub.Firmwares.Upload
  alias Plug.Parsers.MULTIPART

  @impl Plug.Parsers
  def init(opts) do
    # This is called at compile time by default so adding options in runtime.exs
    # will not be captured here and could lead to unknown problems. For dynamic,
    # it will be best to calculate options during the parse phase. Otherwise,
    # all phoenix plugs would need to be set to configure at runtime with
    # `config :phoenix, plug_init_mode: :runtime`
    opts
  end

  @impl Plug.Parsers
  def parse(conn, "multipart", subtype, headers, opts) do
    plug_opts =
      opts
      |> Keyword.put_new_lazy(:length, fn -> max_file_size(conn) end)
      |> MULTIPART.init()

    MULTIPART.parse(conn, "multipart", subtype, headers, plug_opts)
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end

  defp max_file_size(conn) do
    size =
      case conn.path_info do
        ["api", "orgs", _org_name, "products", _product_name, "firmwares"] ->
          Application.get_env(:nerves_hub, Upload)[:max_size]

        ["api", "orgs", _org_name, "products", _product_name, "archives"] ->
          Application.get_env(:nerves_hub, NervesHub.Uploads)[:max_size]

        _ ->
          nil
      end

    if is_integer(size), do: size, else: 1_000_000
  end
end
