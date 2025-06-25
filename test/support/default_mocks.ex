defmodule DefaultMocks do
  use ExUnit.CaseTemplate
  use Mimic

  alias NervesHub.Firmwares.UpdateTool.Fwup
  alias NervesHub.Firmwares.Upload
  alias NervesHub.Firmwares.Upload.File

  setup do
    stub_with(Upload, File)
    stub(Fwup, :delta_updatable?, fn _ -> false end)

    :ok
  end
end
