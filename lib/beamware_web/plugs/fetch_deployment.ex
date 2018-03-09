defmodule BeamwareWeb.Plugs.FetchDeployment do
  import Plug.Conn

  alias Beamware.Deployments

  def init(_), do: nil

  def call(%{assigns: %{tenant: tenant}, params: %{"deployment_id" => deployment_id}} = conn, _) do
    tenant
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
