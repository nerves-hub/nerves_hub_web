defmodule NervesHub.Extensions.Logging.Batched do
  @moduledoc """
  Storing the log lines a device sends, a second's worth per message.

  Version 0.1.0 of the logging extension. `NervesHub.Extensions.Logging` is
  0.0.1, where one message carries one line.

      logging:send  %{"lines" => [%{"level" => .., "message" => ..}, ..]}

  ## Why a second's worth

  NervesHub limits how often a device may send, not how much it may say, and a
  batch costs the same one token as a single line. That is the whole point: a
  device in a crash loop can report everything it wrote in the last second
  rather than losing all but the first few lines to the limiter.

  What stops that becoming an unbounded write is `max_lines_per_message/0`.
  Anything past it is dropped and the count is stored as a log line of its own,
  which is the same bargain the device's own buffer makes: a gap someone can
  see beats a gap they cannot.
  """

  @behaviour NervesHub.Extensions

  alias NervesHub.Devices.LogLines
  alias NervesHub.Extensions.Logging

  require Logger

  @max_lines_per_message 100

  @doc "How many lines one message may carry."
  def max_lines_per_message(), do: @max_lines_per_message

  @impl NervesHub.Extensions
  defdelegate description(), to: Logging

  @impl NervesHub.Extensions
  defdelegate enabled?(), to: Logging

  @impl NervesHub.Extensions
  def attach(state) do
    {state, []}
  end

  @impl NervesHub.Extensions
  def detach(state) do
    {state, []}
  end

  @impl NervesHub.Extensions
  def handle_in("send", %{"lines" => lines}, state) when is_list(lines) do
    if Logging.allow?(state.device_info) do
      {kept, dropped} = Enum.split(lines, @max_lines_per_message)

      _ = LogLines.async_create_many(state.device_info, kept)
      _ = record_overflow(state.device_info, length(dropped))

      :noop
    end

    {state, []}
  end

  # A device on 0.1.0 sends batches. Anything else is a client that declared a
  # version it does not speak, which is worth a line in the log and not worth a
  # crash: `safe_dispatch/5` would rescue it into Sentry, and one device's
  # confusion is not a platform error.
  def handle_in("send", payload, state) do
    Logger.warning("device #{state.device_info.device_id} declared logging 0.1.0 and sent #{inspect(payload)}")

    {state, []}
  end

  @impl NervesHub.Extensions
  def handle_info(_, state) do
    {state, []}
  end

  defp record_overflow(_device_info, 0), do: :ok

  defp record_overflow(device_info, dropped) do
    LogLines.async_create(device_info, %{
      "timestamp" => DateTime.utc_now(),
      "level" => "warning",
      "message" => "NervesHub dropped #{dropped} log lines: a message may carry at most #{@max_lines_per_message}"
    })
  end
end
