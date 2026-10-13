defmodule NervesHub.Integrations.Slack.ClaimsTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Integrations.Slack.Claims
  alias NervesHub.Integrations.Slack.Claims.Claim

  test "a key is claimed once until it expires" do
    assert :ok = Claims.claim("reboot:1", 60, "Alice")
    assert {:held, "Alice", %DateTime{}} = Claims.claim("reboot:1", 60, "Bob")
    assert :ok = Claims.claim("reboot:2", 60, "Bob")
  end

  test "an expired claim can be taken again" do
    :ok = Claims.claim("reboot:1", 60, "Alice")
    {1, _} = Repo.update_all(Claim, set: [expires_at: DateTime.add(DateTime.utc_now(), -1)])

    assert :ok = Claims.claim("reboot:1", 60, "Bob")
    assert {:held, "Bob", _} = Claims.claim("reboot:1", 60, "Carol")
  end

  test "claims long expired are swept away" do
    :ok = Claims.claim("request:old", 60)
    {1, _} = Repo.update_all(Claim, set: [expires_at: DateTime.add(DateTime.utc_now(), -2, :hour)])

    :ok = Claims.claim("request:new", 60)

    assert [%Claim{key: "request:new"}] = Repo.all(Claim)
  end
end
