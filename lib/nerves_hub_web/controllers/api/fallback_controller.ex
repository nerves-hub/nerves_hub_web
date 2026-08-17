defmodule NervesHubWeb.API.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use NervesHubWeb, :api_controller

  alias NervesHubWeb.API.ChangesetJSON
  alias NervesHubWeb.API.ErrorJSON

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status_from_changeset(changeset)
    |> put_view(ChangesetJSON)
    |> render(:error, changeset: changeset)
  end

  def call(conn, {:error, {:product_mismatch, declared, expected}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(ErrorJSON)
    |> render(:"422", %{
      reason: "This firmware is built for the product #{inspect(declared)}, but was uploaded to #{inspect(expected)}."
    })
  end

  def call(conn, {:error, {_key, message}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(ChangesetJSON)
    |> render(:error, message: message)
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(ErrorJSON)
    |> render(:"404")
  end

  def call(conn, {:error, :org_user_not_found}) do
    conn
    |> put_status(422)
    |> put_view(ErrorJSON)
    |> render(:"422", %{
      reason: "A user with that email address could not be found, you may need to invite them instead."
    })
  end

  def call(conn, {:error, :org_user_exists}) do
    conn
    |> put_status(422)
    |> put_view(ErrorJSON)
    |> render(:"422", %{
      reason: "A user with that email address already exists, please use the add user api endpoint."
    })
  end

  def call(conn, {:error, :claimed_elsewhere}) do
    # Deliberately does not say where. Whether another organization holds a key
    # is that organization's business, and this must not become a way to probe
    # for which keys are in use.
    conn
    |> put_status(:conflict)
    |> put_view(ErrorJSON)
    |> render(:"409", %{
      reason:
        "That endpoint id is already registered. If it belongs to one of your devices, " <>
          "it will be claimed the next time that device connects."
    })
  end

  def call(conn, {:error, :invalid_member}) do
    conn
    |> put_status(422)
    |> put_view(ErrorJSON)
    |> render(:"422", %{reason: "That email address does not belong to a member of this organization."})
  end

  def call(conn, {:error, :unknown_owner}) do
    conn
    |> put_status(422)
    |> put_view(ErrorJSON)
    |> render(:"422", %{reason: "owner must be one of: device, user, none."})
  end

  def call(conn, {:error, :unsupported_service}) do
    conn
    |> put_status(422)
    |> put_view(ErrorJSON)
    |> render(:"422", %{reason: "That is not a service this NervesHub knows about."})
  end

  def call(conn, {:error, :authentication_failed}) do
    conn
    |> put_status(401)
    |> put_view(ErrorJSON)
    |> render(:"401", %{reason: "Authentication failed, please check your username and password and try again."})
  end

  def call(conn, {:error, reason}) when is_binary(reason) or is_atom(reason) do
    conn
    |> put_status(500)
    |> put_view(ErrorJSON)
    |> render(:"500", %{reason: to_string(reason)})
  end

  def call(conn, {:error, reason}) do
    conn
    |> put_status(500)
    |> put_view(ErrorJSON)
    |> render(:"500", %{reason: reason})
  end

  def call(conn, :error) do
    conn
    |> put_status(400)
    |> put_view(ErrorJSON)
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
