defmodule NervesHubWeb.Plugs.StaticUploads do
  use NervesHubWeb, :plug

  # This is for the NervesHub.Uploads style of uploads

  def init(_opts), do: []

  def call(conn, _opts) do
    upload_config = Application.get_env(:nerves_hub, NervesHub.Uploads.File, [])

    if upload_config[:enabled] do
      opts = [
        at: upload_config[:public_path],
        from: upload_config[:local_path]
      ]

      init = Plug.Static.init(opts)

      Plug.Static.call(conn, init)
    else
      conn
    end
  end
end
