defmodule NervesHub.Extensions.Logging do
  @moduledoc """
  Storing the log lines a device sends, one line per message.

  This is version 0.0.1 of the extension, and what every device in the field
  speaks today:

      logging:send  %{"level" => "info", "message" => "hello", "meta" => %{..}}

  `NervesHub.Extensions.Logging.Batched` is version 0.1.0, where one message
  carries a second's worth of lines instead of one. Which of the two a device
  gets is decided by the version it declares on the extensions join; see
  `NervesHub.Extensions.module/2`.

  ## The rate limit is per message

  NervesHub limits how often a device may send, not how much it may say. At one
  line per message that makes the limit a limit on lines, which is what 0.1.0
  exists to fix: a device in a crash loop writing hundreds of lines a second
  loses all but the first few here, and the survivors are an arbitrary sample
  rather than the interesting part.
  """

  @behaviour NervesHub.Extensions

  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.LogLines
  alias NervesHub.RateLimit.LogLines, as: RateLimit

  @rate_limit_tokens_per_sec 5
  @rate_limit_max_capacity 10
  @rate_limit_token_cost 1

  @impl NervesHub.Extensions
  def description() do
    """
    Send and store device logs on NervesHub.
    """
  end

  @impl NervesHub.Extensions
  def enabled?() do
    Application.get_env(:nerves_hub, :analytics_enabled)
  end

  @impl NervesHub.Extensions
  def attach(state) do
    {state, []}
  end

  @impl NervesHub.Extensions
  def detach(state) do
    {state, []}
  end

  @impl NervesHub.Extensions
  def handle_in("send", log_line, state) do
    if allow?(state.device_info) do
      _ = LogLines.async_create(state.device_info, log_line)

      :noop
    end

    {state, []}
  end

  @impl NervesHub.Extensions
  def handle_info(_, state) do
    {state, []}
  end

  @doc """
  Whether this device may send now.

  One token per message, whatever the message carries. Shared with
  `NervesHub.Extensions.Logging.Batched` so that both versions of the extension
  draw on the same budget: a device is limited by how often it sends, and
  moving to 0.1.0 changes how much it gets to say, not how often.
  """
  @spec allow?(DeviceInfo.t()) :: boolean()
  def allow?(%DeviceInfo{} = device_info) do
    case RateLimit.hit(
           "device_#{device_info.device_id}",
           @rate_limit_tokens_per_sec,
           @rate_limit_max_capacity,
           @rate_limit_token_cost
         ) do
      {:allow, _} -> true
      {:deny, _} -> false
    end
  end
end
