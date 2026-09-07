defmodule NervesHubWeb.ProductController do
  use NervesHubWeb, :controller

  alias NervesHub.Devices
  alias NervesHub.Devices.DeviceFiltering
  alias NervesHub.Products
  alias NimbleCSV.RFC4180, as: CSV

  @csv_header ["identifier", "description", "tags", "product", "org", "certificates"]

  plug(:validate_role, [org: :view] when action in [:devices_export])

  def devices_export(%{assigns: %{current_scope: scope}} = conn, params) do
    sort = DeviceFiltering.parse_sort(params)

    opts = %{
      filters: params |> DeviceFiltering.parse_filters() |> DeviceFiltering.transform_deployment_filter(),
      sort: {String.to_existing_atom(sort.sort_direction), String.to_existing_atom(sort.sort)}
    }

    devices_query = Devices.filter_query(scope.product, scope.user, opts)

    conn =
      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", ~s[attachment; filename="#{scope.product.name}-devices.csv"])
      |> send_chunked(:ok)

    {:ok, conn} = chunk(conn, CSV.dump_to_iodata([@csv_header]))

    {:ok, conn} =
      Products.devices_export_reducer(devices_query, scope.product, conn, fn conn, line ->
        chunk(conn, CSV.dump_to_iodata([line]))
      end)

    conn
  end
end
