defmodule NervesHubAPIWeb.JITPController do
  use NervesHubAPIWeb, :controller

  alias NervesHubWebCore.Devices

  action_fallback(NervesHubAPIWeb.FallbackController)

  plug(:validate_role, [org: :delete] when action in [:delete])
  plug(:validate_role, [org: :write] when action in [:create])
  plug(:validate_role, [org: :read] when action in [:index, :show])

  def show(%{assigns: %{org: _org}} = conn, %{"ski" => ski64}) do
    with {:ok, ski} <- Base.decode64(ski64),
         {:ok, jitp} <- Devices.get_jitp_by_ski(ski) do
      render(conn, "show.json", jitp: jitp)
    end
  end
end
