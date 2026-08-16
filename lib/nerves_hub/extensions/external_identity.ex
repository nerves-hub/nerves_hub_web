defmodule NervesHub.Extensions.ExternalIdentity do
  @moduledoc """
  Lets a device announce the identities it holds on other networks.

  On attach the server asks once, and the device answers with everything it
  knows about itself — an iroh endpoint id, a NetBird or Tailscale peer key. See
  `NervesHub.Devices.ExternalIdentity` for what is kept and why.

  There is no interval here, unlike `geo` and `health`. An identity is
  long-lived by construction, so polling for it would be noise. A device whose
  *details* have moved (it switched relay, it was assigned a new overlay IP) can
  push `report` again at any time without being asked.
  """

  @behaviour NervesHub.Extensions

  alias NervesHub.Devices.ExternalIdentities

  require Logger

  # There are only a handful of services, and a device holds at most one identity
  # in each. This bounds a malformed or hostile report; it is not a real limit.
  @max_identities 10

  @impl NervesHub.Extensions
  def description() do
    """
    Reporting of identities the device holds on networks NervesHub doesn't run,
    such as an iroh endpoint id or a NetBird, Tailscale or WireGuard public key.
    """
  end

  @impl NervesHub.Extensions
  def enabled?(), do: true

  @impl NervesHub.Extensions
  def attach(state) do
    {state, [{:tick, :request}]}
  end

  @impl NervesHub.Extensions
  def detach(state) do
    {state, []}
  end

  @impl NervesHub.Extensions
  def handle_in("report", %{"identities" => identities}, state) when is_list(identities) do
    device_id = state.device_info.device_id

    identities
    |> Enum.take(@max_identities)
    |> Enum.each(&record(&1, device_id))

    {state, []}
  end

  def handle_in("report", payload, state) do
    # A device on an older or simply wrong version of the client shouldn't take
    # its own connection down over this, so log it and carry on.
    Logger.warning(
      "[ExternalIdentity] device #{state.device_info.device_id} sent an unusable report: " <>
        inspect(payload, limit: 5)
    )

    {state, []}
  end

  @impl NervesHub.Extensions
  def handle_info(:request, state) do
    {state, [{:push, "external_identity:request", %{}}]}
  end

  defp record(%{"service" => service, "identifier" => identifier} = entry, device_id)
       when is_binary(service) and is_binary(identifier) do
    details = Map.get(entry, "details", %{})

    device_id
    |> ExternalIdentities.report(service, %{
      identifier: identifier,
      # Names which endpoint of the service this is, for a device running
      # more than one. The context defaults it when absent.
      instance: Map.get(entry, "instance"),
      details: (is_map(details) && details) || %{}
    })
    |> handled(service, device_id)
  end

  defp record(entry, device_id) do
    Logger.warning(
      "[ExternalIdentity] skipping malformed identity from device #{device_id}: " <>
        inspect(entry, limit: 5)
    )
  end

  # Every outcome the context can return, and none of them disturb the device's
  # connection: a device that cannot record one identity still keeps the others,
  # and still runs.
  defp handled({:ok, _identity}, _service, _device_id), do: :ok

  defp handled({:error, :unsupported_service}, service, device_id) do
    # Expected: a device may legitimately run something we have no schema for.
    Logger.debug(
      "[ExternalIdentity] ignoring unsupported service #{inspect(service)} " <>
        "from device #{device_id}"
    )
  end

  # Both already logged as warnings by the context, which has the detail: an
  # operator recorded something different, or somebody else holds this key.
  defp handled({:error, :operator_managed}, _service, _device_id), do: :ok
  defp handled({:error, :claimed_elsewhere}, _service, _device_id), do: :ok

  # The device was deleted between connecting and reporting. Nothing to record
  # it against, and nothing worth alarming about.
  defp handled({:error, :device_not_found}, _service, _device_id), do: :ok

  defp handled({:error, changeset}, service, device_id) do
    Logger.warning(
      "[ExternalIdentity] could not record #{service} identity for device " <>
        "#{device_id}: #{inspect(changeset.errors)}"
    )
  end
end
