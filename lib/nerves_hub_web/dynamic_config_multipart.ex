defmodule NervesHubWeb.DynamicConfigMultipart do
  @moduledoc """
  A wrapper around `Plug.Parsers.MULTIPART` which allows for the `:length` opt (max file size)
  to be set during runtime.

  This also restricts large file uploads to the firmware upload api route.

  This can later be expanded to allow for different file size limits based on the organization.

  Thank you to https://hexdocs.pm/plug/Plug.Parsers.MULTIPART.html#module-dynamic-configuration
  for the inspiration.
  """
  @behaviour Plug.Parsers

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
      |> Plug.Parsers.MULTIPART.init()

    Plug.Parsers.MULTIPART.parse(conn, "multipart", subtype, headers, plug_opts)
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end

  defp max_file_size(conn) do
    with ["api", "orgs", _org_name, "products", _product_name, "firmwares"] <- conn.path_info,
         size = Application.get_env(:nerves_hub, NervesHub.Firmwares.Upload)[:max_size],
         true <- is_integer(size) do
      size
    else
      _ -> 1_000_000
    end
  end
end
