defmodule DefaultMocks do
  use ExUnit.CaseTemplate

  setup do
    Mox.stub_with(NervesHub.UploadMock, NervesHub.Firmwares.Upload.File)
    Mox.stub(NervesHub.DeltaUpdaterMock, :delta_updatable?, fn _ -> false end)

    :ok
  end
end
