defmodule DefaultMocks do
  use ExUnit.CaseTemplate
  use Mimic

  alias NervesHub.Firmwares.DeltaUpdater.Default
  alias NervesHub.Firmwares.Upload
  alias NervesHub.Firmwares.Upload.File

  setup do
    stub_with(Upload, File)
    stub(Default, :delta_updatable?, fn _ -> false end)

    :ok
  end
end
