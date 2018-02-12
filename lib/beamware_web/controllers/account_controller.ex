defmodule BeamwareWeb.AccountController do
  use BeamwareWeb, :controller

  alias Ecto.Changeset
  alias Beamware.Accounts
  alias Beamware.Accounts.User

  def new(conn, _params) do
    render(conn, "new.html", changeset: %Changeset{data: %User{}})
  end

  def create(conn, params) do
    params["user"]
    |> Accounts.create_tenant()
    |> case do
      {:ok, _tenant} ->
        redirect(conn, to: "/")

      {:error, changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end
end
