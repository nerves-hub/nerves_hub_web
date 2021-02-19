defmodule NervesHubAPIWeb.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use NervesHubAPIWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status_from_changeset(changeset)
    |> put_view(NervesHubAPIWeb.ChangesetView)
    |> render("error.json", changeset: changeset)
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(NervesHubAPIWeb.ErrorView)
    |> render(:"404")
  end

  def call(conn, {:error, reason}) when is_binary(reason) or is_atom(reason) do
    conn
    |> put_resp_content_type("application/json")
    |> put_status(500)
    |> put_view(NervesHubAPIWeb.ErrorView)
    |> send_resp(500, Jason.encode!(%{errors: reason}))
  end

  def call(conn, {:error, reason}) do
    conn
    |> put_status(500)
    |> put_view(NervesHubAPIWeb.ErrorView)
    |> render(:"500", %{reason: reason})
  end

  defp put_status_from_changeset(conn, changeset) do
    status = status_from_changeset_errors(changeset.errors)
    put_status(conn, status)
  end

  defp status_from_changeset_errors(errors) do
    [{error, _} | _] = errors

    if conflict_error?(error) do
      :conflict
    else
      :unprocessable_entity
    end
  end

  defp conflict_error?(error) do
    error in [:deployments, :firmwares, :devices]
  end
end
