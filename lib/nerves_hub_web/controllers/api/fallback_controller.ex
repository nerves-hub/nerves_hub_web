defmodule NervesHubWeb.API.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use NervesHubWeb, :api_controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status_from_changeset(changeset)
    |> put_view(NervesHubWeb.API.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end

  def call(conn, {:error, {key, message}})
      when key in [:no_firmware_uuid, :no_firmware_uploaded, :certificate_decoding_error] do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(NervesHubWeb.API.ChangesetJSON)
    |> render(:error, message: message)
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(NervesHubWeb.API.ErrorJSON)
    |> render(:"404")
  end

  def call(conn, {:error, reason}) when is_binary(reason) or is_atom(reason) do
    conn
    |> put_status(500)
    |> put_view(NervesHubWeb.API.ErrorJSON)
    |> render(:"500", %{reason: to_string(reason)})
  end

  def call(conn, {:error, reason}) do
    conn
    |> put_status(500)
    |> put_view(NervesHubWeb.API.ErrorJSON)
    |> render(:"500", %{reason: reason})
  end

  def call(conn, :error) do
    conn
    |> put_status(400)
    |> put_view(NervesHubWeb.API.ErrorJSON)
    |> render(:"400", %{reason: "An unknown error occurred, please check the request."})
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
    error in [:deployment_groups, :firmwares, :devices]
  end
end
