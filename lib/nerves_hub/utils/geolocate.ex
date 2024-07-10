defmodule NervesHub.Utils.Geolocate do
  def resolve(nil), do: %{}

  def resolve(request_ip) do
    if geo_location_enabled?() do
      request_ip
      |> cache_request()
      |> parse_result()
    else
      %{}
    end
  end

  defp cache_request(request_ip) do
    {:ok, cached_body} = Cachex.get(:geo_ip, request_ip)

    if cached_body do
      cached_body
    else
      case request(request_ip) do
        {:ok, response} ->
          Cachex.put(:geo_ip, request_ip, response.body, ttl: :timer.hours(72))
          response.body

        {:error, _} ->
          %{}
      end
    end
  end

  defp request(request_ip) do
    [
      base_url: "https://geoip.maxmind.com/geoip/v2.1/city/#{request_ip}"
    ]
    |> Keyword.merge(auth: {:basic, maxmind_auth()})
    |> Keyword.merge(Application.get_env(:nerves_hub, :geolocate_middleware, []))
    |> Req.request()
  end

  defp parse_result(%{"code" => code}) do
    %{"error_code" => code}
  end

  defp parse_result(body) do
    body["location"]
    |> Map.put("country", %{
      "name" => body["country"]["names"]["en"],
      "iso_code" => body["country"]["iso_code"]
    })
    |> Map.put("city", body["city"]["names"]["en"])
    |> Map.put("resolution", "geoip")
  end

  defp maxmind_auth(), do: Application.get_env(:nerves_hub, :geoip_maxmind_auth)

  defp geo_location_enabled?(), do: !!maxmind_auth()
end
