defmodule NervesHubWWW.Statistics do
  def devices_per_product(org) do
    pd_counts =
      Enum.reduce(org.devices, %{}, fn d, a ->
        Map.get_and_update(a, d.last_known_firmware.product_id, &count_instances/1)
        |> elem(1)
      end)

    data =
      Enum.reduce(org.products, %{pds: [], cnt: []}, fn p, a ->
        a
        |> Map.merge(%{pds: [p.name | a[:pds]]})
        |> Map.merge(%{cnt: [pd_counts[p.id] | a[:cnt]]})
      end)

    %{
      labels: prep_string_array_for_js(data[:pds]),
      values: prep_array_for_js(data[:cnt])
    }
  end

  def devices_per_firmware(org, product) do
    fw_counts =
      Enum.reduce(org.devices, %{}, fn d, a ->
        Map.get_and_update(a, d.last_known_firmware_id, &count_instances/1)
        |> elem(1)
      end)

    data =
      product.firmwares
      |> Enum.sort(&(&1.inserted_at >= &2.inserted_at))
      |> Enum.reduce(%{fws: [], cnt: []}, fn f, a ->
        a
        |> Map.merge(%{fws: [f.version | a[:fws]]})
        |> Map.merge(%{cnt: [fw_counts[f.id] | a[:cnt]]})
      end)

    %{
      labels: prep_string_array_for_js(data[:fws]),
      values: prep_array_for_js(data[:cnt])
    }
  end

  defp count_instances(curr_val) do
    new_val = if is_nil(curr_val), do: 1, else: curr_val + 1
    {curr_val, new_val}
  end

  defp prep_array_for_js(arr) do
    "[" <> Enum.join(arr, ", ") <> "]"
  end

  defp prep_string_array_for_js(arr) do
    arr
    |> Enum.map(fn i -> "\"" <> i <> "\"" end)
    |> prep_array_for_js
  end
end
