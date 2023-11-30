defmodule NervesHubWeb.Plugs.ConfigureUploads do
  use NervesHubWeb, :plug

  def init(_opts), do: []

  def call(conn, _opts) do
    if System.get_env("FIRMWARE_UPLOAD_BACKEND") == "local" do
      conn
      |> NervesHubWeb.Plugs.FileUpload.call([])
      |> NervesHubWeb.Plugs.StaticUploads.call([])
    else
      conn
    end
  end
end
