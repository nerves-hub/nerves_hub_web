defmodule NervesHubWeb.InviteLinksTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Accounts
  alias NervesHub.Fixtures
  alias NervesHubWeb.Endpoint
  alias NervesHubWeb.InviteLinks

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    {:ok, invite} = Accounts.invite(%{"email" => "joe@example.com", "role" => "view"}, org, user)

    %{invite: invite, org: org}
  end

  test "only the emailed link has a key, which is good for its invite", %{invite: invite} do
    assert URI.parse(InviteLinks.shared_url(invite)).query == nil
    assert InviteLinks.emailed_key?(invite, key(InviteLinks.emailed_url(invite)))
  end

  test "a key stops working once the invite is resent", %{invite: invite, org: org} do
    old_key = key(InviteLinks.emailed_url(invite))
    {:ok, resent} = Accounts.resend_invite(org, invite.token)

    refute InviteLinks.emailed_key?(resent, old_key)
    assert InviteLinks.emailed_key?(resent, key(InviteLinks.emailed_url(resent)))
  end

  test "a key lasts as long as an invite does", %{invite: invite} do
    signed_at = System.system_time(:second) - Accounts.invite_validity_seconds() - 1
    expired = Phoenix.Token.sign(Endpoint, "invite email key", invite.token, signed_at: signed_at)

    refute InviteLinks.emailed_key?(invite, expired)
  end

  test "nothing else is a key", %{invite: invite} do
    refute InviteLinks.emailed_key?(invite, nil)
    refute InviteLinks.emailed_key?(invite, "")
    refute InviteLinks.emailed_key?(invite, invite.token)
    refute InviteLinks.emailed_key?(invite, Phoenix.Token.sign(Endpoint, "another salt", invite.token))
  end

  defp key(url) do
    url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("key")
  end
end
