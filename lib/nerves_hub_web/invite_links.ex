defmodule NervesHubWeb.InviteLinks do
  @moduledoc """
  The two links to an invite.

  Admins can copy an invite's link from the organization's members page and
  pass it on however they like, so registering from it doesn't prove the
  invitee owns the invited address. The link emailed to that address also
  carries a key, signed with the endpoint's secret, that only the email has.
  Registering with the key confirms the new account's email. Registering
  without it leaves the account unconfirmed, and nobody is signed in to it
  until the address is.

  The key is bound to the invite's token, which a resend replaces, and lasts no
  longer than an invite does.
  """

  use NervesHubWeb, :verified_routes

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Invite
  alias NervesHubWeb.Endpoint

  @salt "invite email key"

  @doc """
  The link admins can copy from the members page.
  """
  @spec shared_url(Invite.t()) :: String.t()
  def shared_url(%Invite{token: token}), do: url(~p"/invite/#{token}")

  @doc """
  The link emailed to the invited address, with its key.
  """
  @spec emailed_url(Invite.t()) :: String.t()
  def emailed_url(%Invite{token: token}) do
    url(~p"/invite/#{token}?#{[key: Phoenix.Token.sign(Endpoint, @salt, token)]}")
  end

  @doc """
  Whether `key` came with the link emailed for the invite's current token, and
  hasn't expired.
  """
  @spec emailed_key?(Invite.t(), term()) :: boolean()
  def emailed_key?(%Invite{token: token}, key) when is_binary(key) do
    match?(
      {:ok, ^token},
      Phoenix.Token.verify(Endpoint, @salt, key, max_age: Accounts.invite_validity_seconds())
    )
  end

  def emailed_key?(%Invite{}, _key), do: false
end
