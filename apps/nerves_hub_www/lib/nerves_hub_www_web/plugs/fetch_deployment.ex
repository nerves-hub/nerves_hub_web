defmodule NervesHubWWWWeb.Plugs.FetchDeployment do
  import Plug.Conn

  alias NervesHubCore.Deployments

  def init(_), do: nil

  def call(%{assigns: %{org: org}, params: %{"deployment_id" => deployment_id}} = conn, _) do
    org
    |> Deployments.get_deployment(deployment_id)
    |> case do
      {:ok, deployment} ->
        conn
        |> assign(:deployment, deployment)

      {:error, :not_found} ->
        conn
        |> halt()
    end
  end
end
