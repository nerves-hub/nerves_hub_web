defmodule NervesHub.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  it cannot be async. For this reason, every test runs
  inside a transaction which is reset at the beginning
  of the test unless the test case is marked as async.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox, as: SQLSandbox
  alias NervesHub.Products.HealthProfiles.Cache

  using do
    quote do
      use DefaultMocks
      use Oban.Testing, repo: NervesHub.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import NervesHub.DataCase

      alias NervesHub.Repo

      @moduletag :tmp_dir
    end
  end

  setup tags do
    :ok = SQLSandbox.checkout(NervesHub.Repo)

    # The profile cache outlives the sandbox transaction that is about to be
    # rolled back underneath it.
    :ok = Cache.reset()

    if !tags[:async] do
      SQLSandbox.mode(NervesHub.Repo, {:shared, self()})
    end

    :ok
  end

  @doc """
  Stops the rate limiters' clock moving, for the rest of the test.

  The `Hammer` token buckets behind `NervesHub.RateLimit.*` refill from
  `System.system_time(:second)`, in whole seconds. A test that spends a bucket
  and then expects the next hit to be denied fails whenever the two hits land
  either side of a second boundary, because a token arrives in between. With
  the second held, a denial comes from the limit and never from when the test
  happened to run.

  Use it as `setup :freeze_rate_limit_clock`. Only `System.system_time(:second)`
  is held, and only in the test process: other units, `DateTime.utc_now/0` and
  every other process keep the real clock. `NervesHub.RateLimit.FrozenClockTest`
  fails if Hammer stops reading the time from there.
  """
  def freeze_rate_limit_clock(_context) do
    now = System.system_time(:second)

    Mimic.stub(System, :system_time, fn
      :second -> now
      unit -> Mimic.call_original(System, :system_time, [unit])
    end)

    :ok
  end

  @doc """
  A helper that transform changeset errors to a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
