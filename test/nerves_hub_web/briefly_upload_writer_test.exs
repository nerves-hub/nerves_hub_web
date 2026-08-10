defmodule NervesHubWeb.BrieflyUploadWriterTest do
  use ExUnit.Case, async: true

  alias NervesHubWeb.BrieflyUploadWriter

  test "requires a parent process to take ownership of the temp file" do
    assert_raise KeyError, fn -> BrieflyUploadWriter.init([]) end
  end

  test "the temp file survives beyond the process that created it" do
    parent = self()

    assert %{path: path} =
             Task.async(fn ->
               {:ok, state} = BrieflyUploadWriter.init(parent: parent)
               {:ok, state} = BrieflyUploadWriter.write_chunk("dur", state)
               {:ok, state} = BrieflyUploadWriter.write_chunk("a", state)
               {:ok, state} = BrieflyUploadWriter.write_chunk("ble", state)
               {:ok, state} = BrieflyUploadWriter.close(state, :done)
               BrieflyUploadWriter.meta(state)
             end)
             |> Task.await()

    assert File.exists?(path)
    assert File.read!(path) == "durable"
  end

  test "write_chunk surfaces a write failure instead of silently dropping it" do
    {:ok, state} = BrieflyUploadWriter.init(parent: self())

    # Close the underlying file so the next write cannot succeed; the writer must
    # report the error (per the UploadWriter contract) rather than ignore it.
    :ok = File.close(state.file)

    assert {:error, _reason, ^state} = BrieflyUploadWriter.write_chunk("data", state)
  end

  test "a cancelled upload removes its partial temp file" do
    {:ok, state} = BrieflyUploadWriter.init(parent: self())
    {:ok, state} = BrieflyUploadWriter.write_chunk("partial", state)

    assert {:ok, ^state} = BrieflyUploadWriter.close(state, :cancel)
    refute File.exists?(state.path)
  end
end
