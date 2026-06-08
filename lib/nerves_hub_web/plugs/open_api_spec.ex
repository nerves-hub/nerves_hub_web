defmodule NervesHubWeb.Plugs.OpenApiSpec do
  @moduledoc """
  A copy-paste of `OpenApiSpex.Plug.RenderSpec` that tweaks the JSON encoding
  to use `SortedMap` instead of `Map` for the schemas list.

  Please refer to the OpenApiSpex.Plug.RenderSpec docs for more information.
  """

  @behaviour Plug

  alias OpenApiSpex.Plug.PutApiSpec

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    # credo:disable-for-this-file Credo.Check.Design.AliasUsage
    {spec, _} = PutApiSpec.get_spec_and_operation_lookup(conn)

    {_, spec_map} =
      OpenApiSpex.OpenApi.to_map(spec)
      |> Map.get_and_update("components", fn components ->
        {components, Map.put(components, "schemas", OrderedCollections.new_map(components["schemas"]))}
      end)

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(spec_map))
  end
end
