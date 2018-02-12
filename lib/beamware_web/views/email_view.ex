defmodule BeamwareWeb.EmailView do
  use BeamwareWeb, :view

  def base_url do
    scheme = Application.get_env(:beamware, BeamwareWeb.Endpoint)[:url][:scheme]
    host = Application.get_env(:beamware, BeamwareWeb.Endpoint)[:url][:host]
    port = Application.get_env(:beamware, BeamwareWeb.Endpoint)[:url][:port]
    port = if Enum.member?([443, 80], port), do: "", else: ":#{port}"

    "#{scheme}://#{host}#{port}"
  end
end
