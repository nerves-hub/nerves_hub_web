defmodule NervesHubWeb.Integrations.Slack.ScriptRunsTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Fixtures
  alias NervesHub.Integrations.Slack
  alias NervesHub.Integrations.Slack.ScriptResults
  alias NervesHub.Integrations.Slack.ScriptResults.ScriptResult
  alias NervesHub.Integrations.Slack.UserLink
  alias NervesHubWeb.Integrations.Slack.ScriptRuns

  @response_url "https://hooks.slack.com/actions/T0ACME/2/def"

  setup do
    user = Fixtures.user_fixture()
    test_pid = self()

    Req.Test.stub(Slack, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:responded, Jason.decode!(body)})
      Plug.Conn.send_resp(conn, 200, "ok")
    end)

    Repo.insert!(%UserLink{
      user_id: user.id,
      team_id: "T0ACME",
      slack_user_id: "U0ALICE",
      linked_at: DateTime.utc_now()
    })

    id =
      ScriptResults.store(%{
        user_id: user.id,
        team_id: "T0ACME",
        slack_user_id: "U0ALICE",
        device_identifier: "nh-1",
        script_name: "disk usage",
        output: "/dev/root 42% <!channel>"
      })

    %{result_id: id, user: user}
  end

  defp share(result_id, slack_user_id \\ "U0ALICE") do
    ScriptRuns.share(%{
      result_id: result_id,
      team_id: "T0ACME",
      slack_user_id: slack_user_id,
      response_url: @response_url
    })
  end

  test "posts the output to the channel, as whoever ran it, once", %{result_id: id, user: user} do
    assert :ok = share(id)

    assert_received {:responded, %{"response_type" => "in_channel", "replace_original" => false, "blocks" => blocks}}
    assert [header, output] = Enum.map(blocks, & &1["text"]["text"])
    assert header == "#{user.name} shared the output of `disk usage` on *nh-1*:"
    assert output == "```/dev/root 42% &lt;!channel&gt;```"

    assert_received {:responded,
                     %{"response_type" => "ephemeral", "replace_original" => true, "text" => "Shared in the channel."}}

    assert {:error, :gone} = share(id)
    assert_received {:responded, %{"text" => "That output is no longer kept." <> _}}
  end

  test "only whoever ran the script can share it", %{result_id: id} do
    assert {:error, :not_yours} = share(id, "U0BOB")
    refute_received {:responded, %{"response_type" => "in_channel"}}

    assert :ok = share(id)
  end

  test "not once the Slack user's link has moved to another account", %{result_id: id} do
    other = Fixtures.user_fixture()
    Repo.update_all(UserLink, set: [user_id: other.id])

    assert {:error, :not_linked} = share(id)
    refute_received {:responded, %{"response_type" => "in_channel"}}
  end

  test "output is kept for half an hour", %{result_id: id} do
    Repo.update_all(ScriptResult, set: [inserted_at: DateTime.add(DateTime.utc_now(), -31, :minute)])

    assert {:error, :gone} = share(id)
    assert Repo.all(ScriptResult) == []
  end

  test "a share button with a made-up id does nothing" do
    assert {:error, :gone} = share("not-an-id")
    assert {:error, :gone} = share(Ecto.UUID.generate())
  end
end
