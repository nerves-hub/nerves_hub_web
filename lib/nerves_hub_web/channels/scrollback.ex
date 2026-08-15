defmodule NervesHubWeb.Channels.Scrollback do
  @moduledoc """
  A bounded record of terminal output, kept so a user opening a session can see
  what they missed.

  Belongs to the connection rather than to whatever is interpreting the output:
  it is large, it changes on every line, and nobody outside the connection ever
  needs the whole thing. Console keeps one of these; so does the local shell
  extension, via `NervesHub.DeviceLink.Effect`.
  """

  defstruct buffer: nil, current_line: ""

  @type t() :: %__MODULE__{current_line: String.t(), buffer: CircularBuffer.t()}

  @default_lines 1024

  @spec new(pos_integer()) :: t()
  def new(lines \\ @default_lines), do: %__MODULE__{buffer: CircularBuffer.new(lines)}

  @doc """
  Add raw output, completing whole lines into the buffer and holding the rest.
  """
  @spec append(t(), binary()) :: t()
  def append(%__MODULE__{} = scrollback, data) do
    [current_line | completed] =
      scrollback.current_line
      |> Kernel.<>(data)
      |> String.split("\n")
      |> Enum.reverse()

    buffer =
      completed
      |> Enum.reverse()
      |> Enum.reduce(scrollback.buffer, &CircularBuffer.insert(&2, &1 <> "\n"))

    %{scrollback | current_line: current_line, buffer: buffer}
  end

  @doc "Everything recorded, including the line still being written."
  @spec text(t()) :: String.t()
  def text(%__MODULE__{} = scrollback) do
    Enum.join(scrollback.buffer) <> scrollback.current_line
  end
end
