defmodule NervesHubWeb.Plugs.ConfigureUploads do
  use NervesHubWeb, :plug

  def init(_opts), do: []

  def call(conn, _opts) do

    if local_uploads?() do
      conn
      |> NervesHubWeb.Plugs.FileUpload.call([])
      |> NervesHubWeb.Plugs.StaticUploads.call([])
    else
      conn
    end
  end

  defp local_uploads?() do
    Application.get_env(:nerves_hub, :firmware_upload) == NervesHub.Firmwares.Upload.File
  end
end
