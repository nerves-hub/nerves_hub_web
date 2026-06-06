defmodule NervesHub.Workers.DeleteExpiredCLISessionRecordsTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Accounts
  alias NervesHub.Accounts.UserCLISession
  alias NervesHub.Workers.DeleteExpiredCLISessionRecords

  setup do
    Memento.Table.delete(UserCLISession)
    Memento.Table.create(UserCLISession)

    on_exit(fn ->
      Memento.Table.delete(UserCLISession)
      Memento.Table.create(UserCLISession)
    end)
  end

  test "are cleaned up after they expire (5 mins ttl)" do
    create_cli_session(5)

    assert Memento.transaction!(fn -> Memento.Query.all(UserCLISession) end) |> length() == 1

    Accounts.delete_expired_cli_session_records()

    assert Memento.transaction!(fn -> Memento.Query.all(UserCLISession) end) |> length() == 1

    create_cli_session(-6)

    assert Memento.transaction!(fn -> Memento.Query.all(UserCLISession) end) |> length() == 2

    Accounts.delete_expired_cli_session_records()

    assert Memento.transaction!(fn -> Memento.Query.all(UserCLISession) end) |> length() == 1
  end

  test "are cleaned up after they expire, using the Oban worker (5 mins ttl)" do
    create_cli_session(5)
    create_cli_session(-6)

    assert Memento.transaction!(fn -> Memento.Query.all(UserCLISession) end) |> length() == 2

    assert :ok = perform_job(DeleteExpiredCLISessionRecords, %{})

    assert Memento.transaction!(fn -> Memento.Query.all(UserCLISession) end) |> length() == 1
  end

  defp create_cli_session(mins_ago) do
    token = Ecto.UUID.generate()

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(mins_ago, :minute)
      |> DateTime.to_unix()

    cli_session = %UserCLISession{token: token, status: :waiting, expires_at: expires_at}

    Memento.transaction!(fn -> Memento.Query.write(cli_session) end)
  end
end
