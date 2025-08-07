defmodule NervesHubWeb.Plugs.ConfigureUploads do
  use NervesHubWeb, :plug

  alias NervesHubWeb.Plugs

  def init(_opts), do: []

  def call(conn, _opts) do
    if local_uploads?() do
      conn
      |> Plugs.FileUpload.call([])
      |> Plugs.StaticUploads.call([])
    else
      conn
    end
  end

  defp local_uploads?() do
    Application.get_env(:nerves_hub, :firmware_upload) == NervesHub.Firmwares.Upload.File
  end
end
