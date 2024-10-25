defmodule Mix.Tasks.Gen.Devices do
  use Mix.Task

  @shortdoc "Generate a mass of devices"

  def run([org_name, product_name, count]) do
    Mix.Task.run("app.start")
    count = String.to_integer(count)
    {:ok, org} = NervesHub.Accounts.get_org_by_name(org_name)
    {:ok, product} = NervesHub.Products.get_product_by_org_id_and_name(org.id, product_name)

    current_count =
      NervesHub.Devices.get_device_count_by_org_id_and_product_id(org.id, product.id)

    current_count..(current_count + count)
    |> Enum.map(fn i ->
      if rem(i, 1000) == 0 do
        IO.puts("Created #{i} devices...")
      end

      lng = -180..180 |> Enum.random()
      lat = -90..90 |> Enum.random()

      NervesHub.Devices.create_device(%{
        org_id: org.id,
        product_id: product.id,
        identifier: "generated-#{i}",
        connection_status: :connected,
        connection_established_at: DateTime.now!("Etc/UTC"),
        connection_last_seen_at: DateTime.now!("Etc/UTC"),
        connection_metadata: %{
          "location" => %{
            "longitude" => lng,
            "latitude" => lat,
            "source" => "generated"
          }
        }
      })
    end)
  end
end
