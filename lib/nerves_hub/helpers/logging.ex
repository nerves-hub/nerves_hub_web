defmodule NervesHub.Helpers.Logging do
  def log_to_sentry(device, msg_or_ex, extra \\ %{}) do
    Sentry.Context.set_tags_context(%{
      device_identifier: device.identifier,
      device_id: device.id,
      product_id: device.product_id,
      org_id: device.org_id
    })

    _ =
      if is_exception(msg_or_ex) do
        Sentry.capture_exception(msg_or_ex, extra: extra, result: :none)
      else
        Sentry.capture_message(msg_or_ex, extra: extra, result: :none)
      end

    :ok
  end
end
