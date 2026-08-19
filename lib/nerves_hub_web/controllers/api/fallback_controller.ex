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

  def call(conn, {:error, {:update_tool_not_allowed, tool, product}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(ErrorJSON)
    |> render(:"422", %{
      reason:
        "The product #{inspect(product)} does not accept #{tool} firmware. " <>
          "An organization owner can enable it in the product's settings."
    })
  end

  def call(conn, {:error, :firmware_not_signed}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(ErrorJSON)
    |> render(:"422", %{
      reason:
        "This ESP-IDF image is not signed. NervesHub requires firmware to be signed: sign it with `espsecure.py sign_data --version 2` and register the matching public key against your organization."
    })
  end

  def call(conn, {:error, :esp_idf_ecdsa_signatures_not_supported}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(ErrorJSON)
    |> render(:"422", %{
      reason:
        "This ESP-IDF image is signed with ECDSA. NervesHub can only verify RSA-3072 Secure Boot v2 signatures at present."
    })
  end

  def call(conn, {:error, :unknown_signature_block_version}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(ErrorJSON)
    |> render(:"422", %{reason: "This ESP-IDF image carries a signature block NervesHub does not recognise."})
  end

  def call(conn, {:error, :signature_block_corrupt}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(ErrorJSON)
    |> render(:"422", %{
      reason: "The signature block on this ESP-IDF image failed its checksum — the file is likely damaged in transit."
    })
  end

  def call(conn, {:error, :unrecognised_firmware_format}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(ErrorJSON)
    |> render(:"422", %{
      reason: "Unrecognised firmware format. Expected an fwup archive (.fw) or an ESP-IDF application image (.bin)."
    })
  end

  def call(conn, {:error, {:invalid_version, raw}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(ErrorJSON)
    |> render(:"422", %{
      reason:
        "Firmware version #{inspect(raw)} is not a valid semantic version. For ESP-IDF, set PROJECT_VER in your CMakeLists.txt to something like \"1.2.3\"."
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
