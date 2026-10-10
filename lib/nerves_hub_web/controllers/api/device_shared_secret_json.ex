defmodule NervesHubWeb.API.DeviceSharedSecretJSON do
  @moduledoc """
  Renders device shared secrets.

  Listing renders keys only, built field by field so the secret cannot slip in.
  `created/1` is the one view that includes the secret, and only the actions
  that create a secret render it.
  """

  def index(%{shared_secrets: shared_secrets}) do
    %{data: for(auth <- shared_secrets, do: key_only(auth))}
  end

  def created(%{shared_secret: auth}) do
    %{data: with_secret(auth)}
  end

  @doc """
  A newly created shared secret, including the secret. For create responses only.
  """
  def with_secret(auth) do
    auth
    |> key_only()
    |> Map.put(:secret, auth.secret)
  end

  defp key_only(auth) do
    %{
      key: auth.key,
      deactivated_at: auth.deactivated_at,
      last_used: auth.last_used,
      inserted_at: auth.inserted_at
    }
  end
end
