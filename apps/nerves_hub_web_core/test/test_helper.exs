Logger.remove_backend(:console)
Code.compiler_options(ignore_module_conflict: true)

ExUnit.start(exclude: [:skip])

Ecto.Adapters.SQL.Sandbox.mode(NervesHubWebCore.Repo, :manual)
