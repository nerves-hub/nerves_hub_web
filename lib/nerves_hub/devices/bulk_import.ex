defmodule NervesHub.Devices.BulkImport do
  def parse_file("microchip_trust_and_go", json_payload) do
    {:ok, tng_list} = JSON.decode(json_payload)

    Enum.map(tng_list, fn item ->
      {:ok, tng_raw_decoded} = Base.decode64(item["payload"], padding: false)

      {:ok, tng_decoded} = JSON.decode(tng_raw_decoded)

      pubcert_encoded =
        tng_decoded["publicKeySet"]["keys"]
        |> Enum.find(fn key_entry -> Map.has_key?(key_entry, "x5c") end)
        |> Map.get("x5c")
        |> List.first()

      pubcert_decoded = Base.decode64!(pubcert_encoded, padding: false)

      X509.Certificate.from_der(pubcert_decoded)
      |> case do
        {:ok, cert} ->
          %{
            device_identifier: item["header"]["uniqueId"],
            pem: {:ok, X509.Certificate.to_pem(cert)}
          }

        {:error, _} = error ->
          %{
            device_identifier: item["header"]["uniqueId"],
            pem: error
          }
      end
    end)
  end
end
