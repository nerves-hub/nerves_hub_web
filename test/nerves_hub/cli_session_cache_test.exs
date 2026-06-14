defmodule NervesHub.CLISessionCacheTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Accounts.UserCLISession
  alias NervesHub.CLISessionCache

  setup do
    CLISessionCache.clear()

    on_exit(fn ->
      CLISessionCache.clear()
    end)
  end

  test "are cleaned up after they expire (5 mins ttl)" do
    create_cli_session(5)

    assert CLISessionCache.count() == 1

    :ok = CLISessionCache.delete_expired_sessions()

    assert CLISessionCache.count() == 1

    create_cli_session(-6)

    assert CLISessionCache.count() == 2

    :ok = CLISessionCache.delete_expired_sessions()

    assert CLISessionCache.count() == 1
  end

  test "are cleaned up after they expire" do
    create_cli_session(5)
    create_cli_session(-6)

    assert CLISessionCache.count() == 2

    :ok = CLISessionCache.delete_expired_sessions()

    assert CLISessionCache.count() == 1
  end

  defp create_cli_session(mins_ago) do
    token = Ecto.UUID.generate()

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(mins_ago, :minute)
      |> DateTime.to_unix()

    cli_session = %UserCLISession{token: token, status: :waiting, expires_at: expires_at}

    :ok = NervesHub.CLISessionCache.put(token, cli_session)
  end
end
