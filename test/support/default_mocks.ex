defmodule DefaultMocks do
  use ExUnit.CaseTemplate

  setup do
    Mox.stub_with(NervesHubWebCore.UploadMock, NervesHubWebCore.Firmwares.Upload.File)
    Mox.stub(NervesHubWebCore.PatcherMock, :patchable?, fn _ -> false end)

    :ok
  end
end
