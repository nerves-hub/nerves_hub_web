defmodule NervesHubWWWWeb.NervesKeyController do
  use NervesHubWWWWeb, :controller

  def index(conn, _params) do
    redirect(conn, external: "https://github.com/nerves-hub/nerves_key")
  end
end
