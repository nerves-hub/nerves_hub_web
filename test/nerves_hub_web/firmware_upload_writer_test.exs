defmodule NervesHubWeb.FirmwareUploadWriterTest do
  use ExUnit.Case, async: true

  alias NervesHubWeb.FirmwareUploadWriter

  test "requires a parent process to take ownership of the temp file" do
    assert_raise KeyError, fn -> FirmwareUploadWriter.init([]) end
  end

  test "the temp file survives beyond the process that created it" do
    parent = self()

    assert %{path: path} =
      Task.async(fn ->
        {:ok, state} = FirmwareUploadWriter.init(parent: parent)
        {:ok, state} = FirmwareUploadWriter.write_chunk("dur", state)
        {:ok, state} = FirmwareUploadWriter.write_chunk("a", state)
        {:ok, state} = FirmwareUploadWriter.write_chunk("ble", state)
        {:ok, state} = FirmwareUploadWriter.close(state, :done)
        FirmwareUploadWriter.meta(state)
      end)
      |> Task.await()

    assert File.exists?(path)
    assert File.read!(path) == "durable"
  end
end
