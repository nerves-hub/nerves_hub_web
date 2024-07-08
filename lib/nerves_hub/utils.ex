defmodule NervesHub.Utils do
  def geolocate_ip(nil), do: %{}

  def geolocate_ip(request_ip) do
    if geo_location_enabled?() do
      request_ip
      |> cache_location_request()
      |> parse_result()
    else
      %{}
    end
  end

  defp cache_location_request(request_ip) do
    url = "https://geoip.maxmind.com/geoip/v2.1/city/#{request_ip}"

    case Cachex.fetch(:geo_ip, request_ip, fn _ ->
           auth = {:basic, maxmind_auth()}
           body = Req.get!(url, auth: auth).body
           {:commit, body, ttl: :timer.hours(72)}
         end) do
      {:commit, body, _} -> body
      {:ok, body} -> body
    end
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
