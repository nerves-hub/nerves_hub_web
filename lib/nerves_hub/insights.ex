defmodule NervesHub.Insights do
  @moduledoc """
  Queries for Product Insights.

  Some useful reads, which may inspire future improvements:
  - https://danschultzer.com/posts/normalize-chart-data-using-ecto-postgresql
  - https://danschultzer.com/posts/echarts-phoenix-liveview
  """
  import Ecto.Query

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Products.Product

  alias NervesHub.Repo

  @doc """
  Count of currently connected Devices, scoped to an individual Product.
  """
  @spec connected_count(product :: Product.t()) :: number()
  def connected_count(product) do
    Device
    |> join(:left, [d], lc in assoc(d, :latest_connection), as: :latest_connection)
    |> where([d], d.product_id == ^product.id)
    |> where([_, latest_connection: lc], lc.status == :connected)
    |> Repo.aggregate(:count)
  end

  @doc """
  Count of connected Devices over the last 24 hours, in 1 minute intervals, scoped to an individual Product.
  """
  @spec connected_device_counts_last_24_hours(product :: Product.t()) :: list()
  def connected_device_counts_last_24_hours(product) do
    device_counts_query =
      DeviceConnection
      |> select([dc], %{
        device_count: count(dc.device_id, :distinct)
      })
      |> where([dc], dc.product_id == ^product.id)
      |> where(
        [dc],
        fragment(
          "? BETWEEN DATE_BIN('1 minute'::interval, ?, 'epoch') AND DATE_BIN('1 minute'::interval, ?, 'epoch') + '1 minute'::interval",
          dc.established_at,
          parent_as(:series).timestamp,
          parent_as(:series).timestamp
        ) or
          fragment(
            "? BETWEEN DATE_BIN('1 minute'::interval, ?, 'epoch') AND DATE_BIN('1 minute'::interval, ?, 'epoch') + '1 minute'::interval",
            dc.disconnected_at,
            parent_as(:series).timestamp,
            parent_as(:series).timestamp
          ) or
          (fragment(
             "? < DATE_BIN('1 minute'::interval, ?, 'epoch')",
             dc.established_at,
             parent_as(:series).timestamp
           ) and
             fragment(
               "? > DATE_BIN('1 minute'::interval, ?, 'epoch') + '1 minute'::interval",
               dc.disconnected_at,
               parent_as(:series).timestamp
             )) or
          (fragment(
             "? < DATE_BIN('1 minute'::interval, ?, 'epoch')",
             dc.established_at,
             parent_as(:series).timestamp
           ) and is_nil(dc.disconnected_at))
      )
      |> group_by([dc], dc.product_id)

    from(fragment("GENERATE_SERIES(NOW() - '1 hour'::interval, NOW(), '1 minute'::interval)"),
      as: :series
    )
    |> join(:left_lateral, [], subquery(device_counts_query), on: true, as: :counts)
    |> select([gs, counts: dc], %{
      timestamp:
        fragment("DATE_BIN('1 minute'::interval, ?, 'epoch')", gs) |> selected_as(:timestamp),
      count: coalesce(dc.device_count, 0)
    })
    |> order_by([series: gs], asc: gs.timestamp)
    |> Repo.all()
  end

  @doc """
  Count of devices where the health status isn't 'healthy' or 'unknown', scoped to an individual Product.
  """
  @spec not_healthy_devices_count(product :: Product.t()) :: number()
  def not_healthy_devices_count(product) do
    Device
    |> join(:left, [d], lc in assoc(d, :latest_health), as: :latest_health)
    |> where([d], d.product_id == ^product.id)
    |> where([_, latest_health: lh], lh.status in [:warning, :unhealthy])
    |> Repo.aggregate(:count)
  end

  @doc """
  Count of devices which haven't connected in the last 24 hours, scoped to an individual Product.
  """
  @spec not_recently_seen_count(product :: Product.t()) :: number()
  def not_recently_seen_count(product) do
    Device
    |> join(:left, [d], lc in assoc(d, :latest_connection), as: :latest_connection)
    |> where([d], d.product_id == ^product.id)
    |> where([_, latest_connection: lc], lc.status == :disconnected)
    |> where([_, latest_connection: lc], lc.disconnected_at < ago(24, "hour"))
    |> Repo.aggregate(:count)
  end

  @doc """
  Count of different firmware versions run on connected devices, scoped to an individual Product.
  """
  @spec active_firmware_versions_count(product :: Product.t()) :: number()
  def active_firmware_versions_count(product) do
    Device
    |> select([d], %{version: d.firmware_metadata["uuid"]})
    |> distinct(true)
    |> where([d], d.product_id == ^product.id)
    |> Repo.aggregate(:count)
  end

  @doc """
  List of unique firmware versions run on connected devices, scoped to an individual Product.
  """
  @spec active_firmware_versions(product :: Product.t()) :: list()
  def active_firmware_versions(product) do
    Device
    |> select([d], %{version: d.firmware_metadata["uuid"]})
    |> distinct(true)
    |> where([d], d.product_id == ^product.id)
    |> Repo.all()
  end

  @doc """
  Count of devices which have reconnected more than 5 times in the last 24 hours, scoped to an individual Product.
  """
  @spec high_reconnect_count(product :: Product.t()) :: number()
  def high_reconnect_count(product) do
    Device
    |> join(:left, [d], lc in assoc(d, :device_connections), as: :device_connections)
    |> where([d], d.product_id == ^product.id)
    |> where([_, device_connections: dc], dc.established_at > ago(24, "hour"))
    |> group_by([d], d.id)
    |> having([d, device_connections: dc], count(dc.id) > 5)
    |> subquery()
    |> Repo.aggregate(:count)
  end
end
