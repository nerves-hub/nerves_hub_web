Logger.remove_backend(:console)
Code.compiler_options(ignore_module_conflict: true)

ExUnit.start(exclude: [:pending])

Ecto.Adapters.SQL.Sandbox.mode(NervesHub.Repo, :manual)
