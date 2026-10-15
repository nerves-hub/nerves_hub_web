defmodule NervesHub.Integrations.Slack.SignatureTest do
  use ExUnit.Case, async: true

  alias NervesHub.Integrations.Slack.Signature

  # The worked example in Slack's "Verifying requests from Slack" guide.
  @secret "8f742231b10e8888abcd99yyyzzz85a5"
  @timestamp "1531420618"
  @body "token=xyzz0WbapA4vBCDEFasx0q6G&team_id=T1DC2JH3J&team_domain=testteamnow&channel_id=G8PSS9T3V&channel_name=foobar&user_id=U2CERLKJA&user_name=roadrunner&command=%2Fwebhook-collect&text=&response_url=https%3A%2F%2Fhooks.slack.com%2Fcommands%2FT1DC2JH3J%2F397700885554%2F96rGlfmibIGlgcZRskXaIFfN&trigger_id=398738663015.47445629121.803a0bc887a14d10d2c447fce8b6703c"
  @signature "v0=a2114d57b48eac39b9ad189dd8316235a7b4a8d21a10bd27519666489c69b503"

  test "matches Slack's worked example" do
    assert Signature.sign(@secret, @timestamp, @body) == @signature
    assert :ok = Signature.verify(@secret, @timestamp, @body, @signature, 1_531_420_618 + 60)
  end

  test "refuses a changed body or the wrong secret" do
    now = 1_531_420_618

    assert {:error, :invalid} = Signature.verify(@secret, @timestamp, @body <> "&x=1", @signature, now)
    assert {:error, :invalid} = Signature.verify("another-secret", @timestamp, @body, @signature, now)
    assert {:error, :invalid} = Signature.verify(@secret, "not-a-time", @body, @signature, now)
  end

  test "refuses a request more than five minutes old, or from the future" do
    assert {:error, :stale} = Signature.verify(@secret, @timestamp, @body, @signature, 1_531_420_618 + 301)
    assert {:error, :stale} = Signature.verify(@secret, @timestamp, @body, @signature, 1_531_420_618 - 301)
  end
end
