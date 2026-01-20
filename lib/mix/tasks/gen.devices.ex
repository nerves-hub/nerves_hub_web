defmodule Mix.Tasks.NervesHub.Gen.Devices do
  @shortdoc "Generate a collection of devices"

  @moduledoc """
  Generate a collection of devices for an Organization and Product.

  ## Examples

      mix nerves_hub.gen.devices my-org my-product 1000
  """

  use Mix.Task

  alias NervesHub.Accounts
  alias NervesHub.Devices
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Products
  alias NervesHub.Repo

  @requirements ["app.start"]
  @preferred_cli_env :dev

  @impl Mix.Task
  def run([org_name, product_name, count]) do
    count = String.to_integer(count)
    {:ok, org} = Accounts.get_org_by_name(org_name)
    {:ok, product} = Products.get_product_by_org_id_and_name(org.id, product_name)

    current_count =
      Devices.get_device_count_by_org_id_and_product_id(org.id, product.id)

    current_count..(current_count + count)
    |> Enum.map(fn i ->
      if rem(i, 1000) == 0 do
        IO.puts("Created #{i} devices...")
      end

      lng = -180..180 |> Enum.random()
      lat = -90..90 |> Enum.random()

      {:ok, device} =
        Devices.create_device(%{
          org_id: org.id,
          product_id: product.id,
          identifier: "generated-#{i}"
        })

      %DeviceConnection{
        device_id: device.id,
        established_at: DateTime.utc_now(:millisecond),
        last_seen_at: DateTime.utc_now(:millisecond),
        metadata: %{
          "location" => %{
            "longitude" => lng,
            "latitude" => lat,
            "source" => "generated"
          }
        }
      }
      |> Repo.insert!()
    end)
  end
end
