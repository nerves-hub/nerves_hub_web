Code.compiler_options(ignore_module_conflict: true)

defmodule DefaultMocks do
  use ExUnit.CaseTemplate

  setup do
    Mox.stub_with(NervesHubWebCore.UploadMock, NervesHubWebCore.Firmwares.Upload.File)
    Mox.stub(NervesHubWebCore.DeltaUpdaterMock, :delta_updatable?, fn _ -> false end)

    :ok
  end
end
