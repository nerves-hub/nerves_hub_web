defmodule NervesHub.Helpers.Logging do
  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments.DeploymentGroup

  @doc """
  Helper function for creating issues in Sentry.

  * `resource`: Accepts a Device or Deployment Group. Sets Sentry tags based on type.
  * `message_or_exception`: Binary or Elixir exception.
  * `extra`: A map to provide any other details to Sentry.

  Sets tags for Devices and Deployment Groups. Accepts a binary message or Elixir exception.
  """
  @spec log_to_sentry(DeploymentGroup.t() | Device.t(), binary() | Exception.t(), map()) :: :ok
  def log_to_sentry(resource, msg_or_ex, extra \\ %{}) do
    _ = set_sentry_tags(resource)
    _ = send_to_sentry(msg_or_ex, extra)

    :ok
  end

  @doc """
  Helper function for logging a message to Sentry without a resource.

  * `message`: A binary description.
  * `extra`: A map to provide any other details to Sentry.
  """
  @spec log_message_to_sentry(binary(), map()) :: :ok
  def log_message_to_sentry(message, extra \\ %{}) do
    _ = send_to_sentry(message, extra)

    :ok
  end

  defp set_sentry_tags(%Device{} = device),
    do:
      Sentry.Context.set_tags_context(%{
        device_identifier: device.identifier,
        device_id: device.id,
        product_id: device.product_id,
        org_id: device.org_id
      })

  defp set_sentry_tags(%DeploymentGroup{} = deployment_group),
    do:
      Sentry.Context.set_tags_context(%{
        deployment: deployment_group.name,
        product_id: deployment_group.product_id,
        org_id: deployment_group.org_id
      })

  defp send_to_sentry(exception, extra) when is_exception(exception),
    do: Sentry.capture_exception(exception, extra: extra, result: :none)

  defp send_to_sentry(message, extra),
    do: Sentry.capture_message(message, extra: extra, result: :none)
end
