defmodule NervesHubWeb.FirmwareUploadWriter do
  @moduledoc """
  A `Phoenix.LiveView.UploadWriter` that streams uploaded firmware chunks
  directly to a durable temporary file.
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
    IO.binwrite(state.file, data)
    {:ok, state}
  end

  @impl UploadWriter
  def close(state, _reason) do
    with :ok <- File.close(state.file),
         :ok <- Briefly.give_away(state.path, state.parent) do
      {:ok, state}
    end
  end
end
