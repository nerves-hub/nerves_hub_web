defmodule NervesHubWeb.BrieflyUploadWriter do
  @moduledoc """
  A `Phoenix.LiveView.UploadWriter` that streams uploaded chunks directly to a
  durable temporary file created by `Briefly`, avoiding a second copy when the
  LiveView consumes the entry.

  `Briefly.create/0` ties the temp file's lifetime to the process that created
  it — here the channel uploader process the writer runs in. On a completed
  upload (`close/2` with `:done`) ownership is handed to the `:parent` process
  passed to `init/1` via `Briefly.give_away/2`, so the file outlives the upload
  and is instead reaped when the parent (the LiveView) exits. On a cancelled or
  errored upload the entry is never consumed, so the partial file is removed
  immediately rather than left for process-exit cleanup.
  """
  @behaviour Phoenix.LiveView.UploadWriter

  alias Phoenix.LiveView.UploadWriter

  @impl UploadWriter
  def init(opts) do
    parent = Keyword.fetch!(opts, :parent)

    with {:ok, path} <- Briefly.create(),
         {:ok, file} <- File.open(path, [:binary, :write]) do
      {:ok, %{path: path, file: file, parent: parent}}
    end
  end

  @impl UploadWriter
  def meta(state), do: %{path: state.path}

  @impl UploadWriter
  def write_chunk(data, state) do
    # `IO.binwrite/2` to a file device signals write failures (a full or
    # read-only disk, a closed handle) by raising, not by returning an error
    # tuple. Catch it and return `{:error, reason, state}` so the upload is
    # cancelled cleanly — `close/2` is then called with `{:error, reason}` —
    # instead of crashing the channel process the writer runs in.
    IO.binwrite(state.file, data)
    {:ok, state}
  rescue
    error -> {:error, error, state}
  end

  @impl UploadWriter
  def close(state, reason) do
    # Close the file handle first so the OS flushes it regardless of how the
    # upload ended; `File.close/1` on an already-closed handle is harmless.
    _ = File.close(state.file)

    case reason do
      :done ->
        # Hand the finished file to the parent (the LiveView) so it survives this
        # writer and Briefly reaps it when the parent exits.
        case Briefly.give_away(state.path, state.parent) do
          :ok -> {:ok, state}
          {:error, give_away_error} -> {:error, give_away_error}
        end

      _ ->
        # Cancelled or errored: the entry is never consumed, so drop the partial
        # temp file now instead of leaving it until the uploader process exits.
        _ = File.rm(state.path)
        {:ok, state}
    end
  end
end
