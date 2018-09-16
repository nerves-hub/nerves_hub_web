Logger.remove_backend(:console)
Code.compiler_options(ignore_module_conflict: true)

ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(NervesHubCore.Repo, :manual)
