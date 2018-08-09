Logger.remove_backend(:console)

assert_timeout = String.to_integer(
  System.get_env("ELIXIR_ASSERT_TIMEOUT") || "200"
)

ExUnit.start(assert_receive_timeout: assert_timeout)

Ecto.Adapters.SQL.Sandbox.mode(NervesHubCore.Repo, :manual)
