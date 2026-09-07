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

  # Only a newline moves output into the bounded buffer, so a device that never
  # sends one -- a `\r` progress bar, a loop of `IO.write/1`, raw bytes -- grew
  # `current_line` without limit inside a process that lives as long as the
  # connection. Past this many bytes we bank what we have and carry on.
  @max_line_bytes 1024

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

    bank_overlong_line(%{scrollback | current_line: current_line, buffer: buffer})
  end

  # Banked pieces carry no newline of their own, so `text/1` still stitches the
  # original stream back together. Splitting on graphemes rather than bytes
  # keeps the pieces from cutting a codepoint in half; the guard stays on
  # `byte_size/1` because it runs on every line of output.
  defp bank_overlong_line(%__MODULE__{current_line: line} = scrollback) when byte_size(line) >= @max_line_bytes do
    {banked, rest} = String.split_at(line, @max_line_bytes)

    bank_overlong_line(%{
      scrollback
      | current_line: rest,
        buffer: CircularBuffer.insert(scrollback.buffer, banked)
    })
  end

  defp bank_overlong_line(scrollback), do: scrollback

  @doc "Everything recorded, including the line still being written."
  @spec text(t()) :: String.t()
  def text(%__MODULE__{} = scrollback) do
    Enum.join(scrollback.buffer) <> scrollback.current_line
  end
end
