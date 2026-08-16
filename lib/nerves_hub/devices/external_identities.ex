defmodule NervesHub.Devices.ExternalIdentities do
  @moduledoc """
  Context for the identities a device holds on networks NervesHub does not run.

  See `NervesHub.Devices.ExternalIdentity` for what is stored and why.

  Writes arrive from two places with very different trust: a device announcing
  itself over its socket, and (later) an operator recording an identity by hand.
  `report/3` is the device-facing path and is deliberately the more restricted
  of the two.
  """

  import Ecto.Query

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.ExternalIdentity
  alias NervesHub.Repo
  alias Phoenix.Channel.Server, as: ChannelServer

  require Logger

  @doc """
  All identities recorded for a device, ordered by service then instance.
  """
  @spec list_for_device(pos_integer()) :: [ExternalIdentity.t()]
  def list_for_device(device_id) do
    ExternalIdentity
    |> where(device_id: ^device_id)
    |> order_by(asc: :service, asc: :instance)
    |> Repo.all()
  end

  @doc """
  Fetch a device's identity for one endpoint of one service.

  `instance` distinguishes two endpoints of the same service on one device — an
  iroh console and an iroh application, say. Services that are singletons use
  the default.
  """
  @spec get(pos_integer(), atom(), String.t()) ::
          {:ok, ExternalIdentity.t()} | {:error, :not_found}
  def get(device_id, service, instance \\ ExternalIdentity.default_instance()) do
    ExternalIdentity
    |> where(device_id: ^device_id)
    |> where(service: ^service)
    |> where(instance: ^instance)
    |> Repo.fetch()
  end

  @doc """
  Fetch the device that proved possession of `identifier` on `service`.

  The reverse of `get/3`: that one starts from a device, this one starts from
  the key. `ExternalIdentity` carries a unique index on `(service, identifier)`
  precisely so this is a point lookup — a key belongs to at most one device.

  A soft-deleted device comes back as `{:error, :device_deleted}` rather than
  `{:error, :not_found}`. Both mean "do not admit this key", but they mean
  different things to whoever reads the logs: one is a key nobody ever
  registered, the other a device removed while still holding one.

  Matching is exact, and nothing here normalises case, because it cannot: an
  iroh endpoint id is hex and case-insensitive in practice, while a WireGuard
  public key is base64 and is not. Reporter and caller have to agree on a form,
  and for iroh that is the lowercase hex `EndpointId` renders.

  ## Called over `:erpc` by other applications in the cluster

  **This function has no callers inside nerves_hub_web, and that is expected.
  It is not unused — do not remove it.** See "Cross-application contracts" in
  `AGENTS.md`.

  Today's caller is the iroh relay authorization service, which answers
  `iroh-relay`'s access hook. A relay first proves the endpoint holds the
  private key for the endpoint id it claims, then asks whether that key belongs
  to a device we know and which organisation owns it. The organisation becomes
  the relay "fabric", which is what stops one customer's devices reaching
  another's.

  Being an `:erpc` target shapes the return value in two ways:

    * **It returns a map, not a struct.** A struct arriving on a node that does
      not define its module is a map carrying a `__struct__` key pointing at
      nothing, which callers then work around. Named keys survive the hop.

    * **Its shape is a published interface.** Adding a key is safe; renaming or
      removing one breaks a caller this repository cannot see and will not fail
      to compile against. The test pins the shape for that reason.
  """
  @spec get_device_by_identifier(atom() | String.t(), String.t()) ::
          {:ok, map()} | {:error, :not_found | :device_deleted | :unsupported_service}
  def get_device_by_identifier(service, identifier) when is_binary(identifier) do
    case cast_service(service) do
      {:ok, service} -> device_by_identifier(service, identifier)
      :error -> {:error, :unsupported_service}
    end
  end

  defp device_by_identifier(service, identifier) do
    ExternalIdentity
    |> where(service: ^service)
    |> where(identifier: ^identifier)
    |> join(:inner, [ei], d in Device, on: d.id == ei.device_id)
    |> select([ei, d], %{
      device_id: d.id,
      device_identifier: d.identifier,
      org_id: d.org_id,
      product_id: d.product_id,
      service: ei.service,
      instance: ei.instance,
      deleted_at: d.deleted_at
    })
    |> Repo.fetch()
    |> case do
      {:ok, %{deleted_at: nil} = found} -> {:ok, Map.delete(found, :deleted_at)}
      {:ok, _deleted} -> {:error, :device_deleted}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc """
  Record an identity a device has reported about itself.

  Returns `{:error, :unsupported_service}` for a service this NervesHub does not
  know about. A device is free to run something we have no schema for, and that
  must not disturb its connection — the caller is expected to skip it.

  Returns `{:error, :operator_managed}` when an operator has recorded a
  different identity for this device, service and instance. That disagreement is
  worth surfacing rather than resolving silently: it means the device was
  reflashed, its state partition was wiped, or something is claiming to be it.

  `attrs` may carry an `:instance` naming which endpoint of the service this is.
  A device running both an iroh console and an iroh application reports each
  under its own instance; anything that omits one is the service's only endpoint.
  """
  @spec report(pos_integer(), atom() | String.t(), map()) ::
          {:ok, ExternalIdentity.t()}
          | {:error, :unsupported_service | :operator_managed | Ecto.Changeset.t()}
  def report(device_id, service, attrs) do
    case cast_service(service) do
      {:ok, service} -> do_report(device_id, service, attrs)
      :error -> {:error, :unsupported_service}
    end
  end

  defp do_report(device_id, service, attrs) do
    identifier = attrs[:identifier] || attrs["identifier"]
    details = attrs[:details] || attrs["details"] || %{}
    instance = cast_instance(attrs[:instance] || attrs["instance"])

    case get(device_id, service, instance) do
      {:error, :not_found} ->
        %ExternalIdentity{}
        |> ExternalIdentity.changeset(%{
          device_id: device_id,
          service: service,
          instance: instance,
          identifier: identifier,
          details: details,
          source: :device_reported,
          last_reported_at: DateTime.utc_now()
        })
        |> Repo.insert()
        |> broadcast_if_ok(device_id)

      {:ok, %ExternalIdentity{source: :operator} = existing} ->
        if existing.identifier == identifier do
          # The device agrees with what the operator recorded, so record that we
          # heard from it and leave the row otherwise untouched.
          touch(existing)
        else
          Logger.warning(
            "[ExternalIdentities] device #{device_id} reported a #{service}/#{instance} identity " <>
              "that differs from the operator-recorded one; ignoring the device's value"
          )

          {:error, :operator_managed}
        end

      {:ok, existing} ->
        update(existing, identifier, details, device_id)
    end
  end

  # An absent or unusable instance means "this service's only endpoint". Devices
  # that run one of something shouldn't have to say so.
  defp cast_instance(instance) when is_binary(instance) do
    case String.trim(instance) do
      "" -> ExternalIdentity.default_instance()
      trimmed -> trimmed
    end
  end

  defp cast_instance(instance) when is_atom(instance) and not is_nil(instance), do: Atom.to_string(instance)

  defp cast_instance(_instance), do: ExternalIdentity.default_instance()

  defp update(existing, identifier, details, device_id) do
    changed? = existing.identifier != identifier or existing.details != details

    existing
    |> ExternalIdentity.changeset(%{
      identifier: identifier,
      details: details,
      last_reported_at: DateTime.utc_now()
    })
    |> Repo.update()
    |> then(fn result ->
      # A device re-reports the same identity on every reconnect. Only tell the
      # UI when something actually moved, rather than re-rendering every open
      # device page on each connect.
      if changed?, do: broadcast_if_ok(result, device_id), else: result
    end)
  end

  defp touch(%ExternalIdentity{} = identity) do
    identity
    |> ExternalIdentity.changeset(%{last_reported_at: DateTime.utc_now()})
    |> Repo.update()
  end

  defp broadcast_if_ok({:ok, identity} = result, device_id) do
    _ =
      ChannelServer.broadcast(
        NervesHub.PubSub,
        "internal:device:#{device_id}",
        "external_identities:updated",
        %{service: identity.service}
      )

    result
  end

  defp broadcast_if_ok(result, _device_id), do: result

  defp cast_service(service) when is_atom(service) do
    if service in ExternalIdentity.services(), do: {:ok, service}, else: :error
  end

  defp cast_service(service) when is_binary(service) do
    # String.to_existing_atom/1 is not enough on its own — every service name is
    # already an existing atom, so it would happily return one we do not support.
    Enum.find_value(ExternalIdentity.services(), :error, fn known ->
      if Atom.to_string(known) == service, do: {:ok, known}
    end)
  end

  defp cast_service(_service), do: :error
end
