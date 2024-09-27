defmodule NervesHub.Features do
  @moduledoc """
  A "feature" is an additional piece of functionality that we add onto the
  existing connection between the device and the NervesHub service. They are
  designed to be less important than firmware updates and requires both client
  to report support and the server to enable support.

  This is intended to ensure that:

  - The service decides when activity should be taken by the device meaning
    the fleet of devices will not inadvertently swarm the service with data.
  - The service can turn off features in various ways to ensure that disruptive
    features stop being enabled on subsequent connections.
  - Use of features should have very little chance to disrupt the flow of a
    critical firmware update.
  """

  alias NervesHub.Devices.Device

  require Logger

  @doc """
  Whether a device is allowed to use features at all, currently.

  This currently consults the static configuration to see if features are
  enabled overall. We should later add subsequent checks as features may
  be controlled per product or per
  """
  @spec device_can_use_features?(Device.t()) :: boolean()
  def device_can_use_features?(%Device{} = _device) do
    # Launch features feature with a restrictive default, this may change later
    Application.get_env(:nerves_hub, :use_features?, false)
  end

  @doc """
  Whether a specific feature is allowed at a specific version for a device.

  This currently consults the static configuration to see if features are
  enabled overall. We should later add subsequent checks as features may
  be controlled per organisation, per product and/or per device.

  This starts with that very rough on off switch for all features and
  then also some global config for specific features that defaults to off.
  """
  @spec enable_feature?(Device.t(), String.t(), String.t()) :: boolean()
  def enable_feature?(%Device{} = _device, feature, version) do
    Application.get_env(:nerves_hub, :use_features?, false) and
      enable_from_config?(feature, version)
  end

  defp enable_from_config?(feature, version) do
    features = Application.get_env(:nerves_hub, :features, [])

    case features[feature] do
      nil ->
        false

      # Generically enabled
      true ->
        true

      # Configured
      config when is_map(config) or is_list(config) ->
        config_version_requirement_matched?(config[:version], version)

      bad ->
        Logger.error("Invalid config for feature '#{feature}, configured as: #{inspect(bad)}")
        false
    end
  end

  # If no version was set in config it is enabled
  defp config_version_requirement_matched?(nil, _), do: true

  defp config_version_requirement_matched?(requirement, version) do
    Version.match?(version, requirement)
  end
end
