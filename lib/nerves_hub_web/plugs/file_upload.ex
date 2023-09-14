defmodule NervesHubWeb.Plugs.FileUpload do
  use NervesHubWeb, :plug

  def init(_opts), do: []

  def call(conn, _opts) do
    file_upload_config = Application.get_env(:nerves_hub, NervesHub.Firmwares.Upload.File, [])

    if file_upload_config[:enabled] do
      opts = [
        at: file_upload_config[:public_path],
        from: file_upload_config[:local_path]
      ]

      init = Plug.Static.init(opts)

      Plug.Static.call(conn, init)
    else
      conn
    end
  end
end
