defmodule NervesHubWeb.Plugs.ConfigureUploads do
  use NervesHubWeb, :plug

  alias NervesHubWeb.Plugs.FileUpload
  alias NervesHubWeb.Plugs.StaticUploads

  def init(_opts), do: []

  def call(conn, _opts) do
    if local_uploads?() do
      conn
      |> FileUpload.call([])
      |> StaticUploads.call([])
    else
      conn
    end
  end

  defp local_uploads?() do
    Application.get_env(:nerves_hub, :firmware_upload) == NervesHub.Firmwares.Upload.File
  end
end
