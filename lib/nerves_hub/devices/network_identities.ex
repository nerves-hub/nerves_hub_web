defmodule NervesHub.Devices.NetworkIdentities do
  @moduledoc """
  Context for identities held on networks NervesHub does not run.

  See `NervesHub.Devices.NetworkIdentity` for what is stored and why, including
  who can hold one: a device, a membership, or nobody in particular.

  Writes arrive from two places with very different trust. A device announcing
  itself over its own connection has proven the key it is reporting. An operator
  typing one into a form has proven nothing — they may have mistyped it, or be
  claiming a key belonging to somebody else.

  That asymmetry decides the rules here:

    * A device **takes over** a key an operator recorded by hand in the same
      organisation. Possession beats assertion, and this is the intended flow:
      register a key, then watch the device claim it.
    * A device is **refused** a key held in another organisation, loudly. Left to
      the unique index it would fail on every reconnect forever, looking like a
      network fault rather than the conflict it is.
    * An operator is **refused** a key already known anywhere else, for the same
      reason from the other side: first-come-wins on an unproven key lets one
      organisation take another's traffic, or squat a key so its real owner can
      never register.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.User
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.NetworkIdentity
  alias NervesHub.Devices.PubSub
  alias NervesHub.Repo

  require Logger

  @doc """
  All identities recorded for a device, ordered by service then instance.

  `opts` narrows the list:

    * `:service` — only this protocol, as an atom. Cast a name that arrived from
      outside with `cast_service/1` first; an unsupported one should be an error
      to its caller rather than quietly the whole list.
    * `:instance` — only this endpoint of it, matched exactly.
  """
  @spec list_for_device(pos_integer(), keyword()) :: [NetworkIdentity.t()]
  def list_for_device(device_id, opts \\ []) do
    NetworkIdentity
    |> where(device_id: ^device_id)
    |> filter_by_service(opts[:service])
    |> filter_by_instance(opts[:instance])
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
          {:ok, NetworkIdentity.t()} | {:error, :not_found}
  def get(device_id, service, instance \\ NetworkIdentity.default_instance()) do
    NetworkIdentity
    |> where(device_id: ^device_id)
    |> where(service: ^service)
    |> where(instance: ^instance)
    |> Repo.fetch()
  end

  @doc """
  Identities belonging to an organisation, newest first.

  `opts` narrows the list:

    * `:service` — only this protocol.
    * `:owner` — `:device`, `:org_user`, or `:unowned`.
    * `:search` — matches the start of an identifier, or anywhere in a device's
      identifier or a user's name. Prefix rather than substring on the key
      because that is the half an operator has: logs and tables show a key
      truncated, so the beginning is what they can copy.

  Owners are preloaded, since a list of keys without whose they are is not much
  of a list.
  """
  @spec list_for_org(pos_integer(), keyword()) :: [NetworkIdentity.t()]
  def list_for_org(org_id, opts \\ []) do
    NetworkIdentity
    |> where(org_id: ^org_id)
    |> filter_by_service(opts[:service])
    |> filter_by_owner(opts[:owner])
    |> filter_by_search(opts[:search])
    |> order_by([ei], desc: ei.inserted_at, asc: ei.id)
    |> preload([:device, org_user: :user])
    |> Repo.all()
  end

  defp filter_by_service(query, nil), do: query
  defp filter_by_service(query, service), do: where(query, service: ^service)

  defp filter_by_instance(query, nil), do: query
  defp filter_by_instance(query, instance), do: where(query, instance: ^instance)

  defp filter_by_owner(query, nil), do: query
  defp filter_by_owner(query, :device), do: where(query, [ei], not is_nil(ei.device_id))
  defp filter_by_owner(query, :org_user), do: where(query, [ei], not is_nil(ei.org_user_id))

  defp filter_by_owner(query, :unowned), do: where(query, [ei], is_nil(ei.device_id) and is_nil(ei.org_user_id))

  defp filter_by_owner(query, _other), do: query

  defp filter_by_search(query, search) when is_binary(search) do
    case String.trim(search) do
      "" ->
        query

      term ->
        prefix = escape_like(term) <> "%"
        anywhere = "%" <> escape_like(term) <> "%"

        query
        |> join(:left, [ei], d in Device, on: d.id == ei.device_id, as: :device)
        |> join(:left, [ei], ou in OrgUser, on: ou.id == ei.org_user_id, as: :org_user)
        |> join(:left, [org_user: ou], u in User, on: u.id == ou.user_id, as: :user)
        |> where(
          [ei, device: d, user: u],
          ilike(ei.identifier, ^prefix) or ilike(d.identifier, ^anywhere) or
            ilike(u.name, ^anywhere)
        )
    end
  end

  defp filter_by_search(query, _search), do: query

  # A search for "abc_" should look for that, not treat the underscore as a
  # wildcard and match everything.
  defp escape_like(term) do
    String.replace(term, ["\\", "%", "_"], fn char -> "\\" <> char end)
  end

  @doc """
  Record an identity by hand, against an organisation.

  For something NervesHub does not manage — a laptop, a jump host — or for a
  device being registered before it first connects, which then claims the row
  itself. Pass `:org_user_id` to attach it to a membership, or leave it off for
  an identity the organisation holds directly.

  Returns `{:error, :claimed_elsewhere}` when the key is already recorded
  anywhere, including in another organisation. Nothing about a typed-in key is
  proven, so first-come-wins would let one organisation take another's traffic
  by registering a key it does not hold — or squat one so its real owner never
  can. The caller is expected to say so plainly rather than retry.

  Returns `{:error, :invalid_member}` when `:org_user_id` names a membership of
  some other organisation. The id arrives from a form and is therefore a
  request, not a fact: without this, a crafted one would attach a key to
  somebody outside the organisation doing the registering.
  """
  @spec register(pos_integer(), atom() | String.t(), map()) ::
          {:ok, NetworkIdentity.t()}
          | {:error, :unsupported_service | :claimed_elsewhere | :invalid_member | Ecto.Changeset.t()}
  def register(org_id, service, attrs) do
    with {:ok, service} <- cast_service_result(service),
         {:ok, org_user_id} <- cast_member(org_id, attrs[:org_user_id] || attrs["org_user_id"]) do
      identifier = attrs[:identifier] || attrs["identifier"]

      if is_binary(identifier) and Repo.exists?(claimed_query(service, identifier)) do
        {:error, :claimed_elsewhere}
      else
        %NetworkIdentity{}
        |> NetworkIdentity.changeset(%{
          org_id: org_id,
          org_user_id: org_user_id,
          service: service,
          instance: cast_instance(attrs[:instance] || attrs["instance"]),
          identifier: identifier,
          details: attrs[:details] || attrs["details"] || %{},
          source: :operator
        })
        |> Repo.insert()
      end
    end
  end

  # "" arrives from a select whose blank option means "nobody".
  defp cast_member(_org_id, nil), do: {:ok, nil}
  defp cast_member(_org_id, ""), do: {:ok, nil}

  defp cast_member(org_id, org_user_id) do
    with {:ok, id} <- cast_member_id(org_user_id),
         true <- Repo.exists?(member_query(org_id, id)) do
      {:ok, id}
    else
      _other -> {:error, :invalid_member}
    end
  end

  defp cast_member_id(id) when is_integer(id), do: {:ok, id}

  defp cast_member_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> {:ok, parsed}
      _other -> :error
    end
  end

  defp cast_member_id(_id), do: :error

  defp member_query(org_id, org_user_id) do
    OrgUser
    |> where(id: ^org_user_id)
    |> where(org_id: ^org_id)
    |> where([ou], is_nil(ou.deleted_at))
  end

  defp claimed_query(service, identifier) do
    NetworkIdentity
    |> where(service: ^service)
    |> where(identifier: ^identifier)
  end

  @doc """
  Fetch one of an organisation's identities by the key it names.

  Scoped to the organisation, because a key is not a secret — it is the one
  thing an outsider is most likely to have — so knowing one must not be enough
  to read the record another organisation keeps of it.

  Owners are preloaded, since whose a key is is most of what there is to say
  about it.
  """
  @spec get_for_org(pos_integer(), atom() | String.t(), String.t()) ::
          {:ok, NetworkIdentity.t()} | {:error, :not_found | :unsupported_service}
  def get_for_org(org_id, service, identifier) when is_binary(identifier) do
    with {:ok, service} <- cast_service_result(service) do
      NetworkIdentity
      |> where(org_id: ^org_id)
      |> where(service: ^service)
      |> where(identifier: ^identifier)
      |> preload([:device, org_user: :user])
      |> Repo.fetch()
    end
  end

  @doc """
  Remove an identity.

  Scoped to an organisation so a caller cannot delete one belonging to another
  by guessing an id.
  """
  @spec delete(pos_integer(), pos_integer()) :: {:ok, NetworkIdentity.t()} | {:error, :not_found}
  def delete(org_id, id) do
    NetworkIdentity
    |> where(id: ^id)
    |> where(org_id: ^org_id)
    |> Repo.fetch()
    |> case do
      {:ok, identity} -> Repo.delete(identity)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc """
  Fetch the owner that proved possession of `identifier` on `service`.

  The reverse of `get/3`: that one starts from a device, this one starts from
  the key. `(service, identifier)` is unique across the whole table, so this is
  a point lookup and a key resolves to exactly one organisation.

  Returns the organisation the key speaks for, and who holds it — a device, a
  membership, or neither for one an operator recorded by hand.

  An identity whose owner has been removed is refused, not returned. Devices and
  memberships are both soft deleted, so the rows survive; treating them as live
  would let a decommissioned device, or somebody removed from an organisation,
  keep whatever access the key grants. `{:error, :owner_deleted}` says so
  distinctly from `{:error, :not_found}` — both mean refuse, but one is a key
  nobody registered and the other is access that has been taken away.

  Matching is exact, and nothing here normalises case, because it cannot: an
  iroh endpoint id is hex and case-insensitive in practice, while a WireGuard
  public key is base64 and is not. Reporter and caller have to agree on a form,
  and for iroh that is the lowercase hex `EndpointId` renders.

  ## Called over `:erpc` by other applications in the cluster

  **This function has no callers inside nerves_hub_web, and that is expected.
  It is not unused — do not remove it.** See "Cross-application contracts" in
  `AGENTS.md`.

  Today's caller answers a relay's access check: the relay proves the peer holds
  the private key for the endpoint id it claims, then asks whether that key is
  one of ours and which organisation it belongs to. The organisation decides
  which network the peer is placed on, which is what stops one customer's
  devices reaching another's.

  Being an `:erpc` target shapes the return value in two ways:

    * **It returns a map, not a struct.** A struct arriving on a node that does
      not define its module is a map carrying a `__struct__` key pointing at
      nothing, which callers then work around. Named keys survive the hop.

    * **Its shape is a published interface.** Adding a key is safe; renaming or
      removing one breaks a caller this repository cannot see and will not fail
      to compile against. The test pins the shape for that reason.
  """
  @spec get_owner_by_identifier(atom() | String.t(), String.t()) ::
          {:ok, map()} | {:error, :not_found | :owner_deleted | :unsupported_service}
  def get_owner_by_identifier(service, identifier) when is_binary(identifier) do
    case cast_service(service) do
      {:ok, service} -> owner_by_identifier(service, identifier)
      :error -> {:error, :unsupported_service}
    end
  end

  defp owner_by_identifier(service, identifier) do
    NetworkIdentity
    |> where(service: ^service)
    |> where(identifier: ^identifier)
    |> join(:left, [ei], d in Device, on: d.id == ei.device_id)
    |> join(:left, [ei, _d], ou in OrgUser, on: ou.id == ei.org_user_id)
    |> select([ei, d, ou], %{
      org_id: ei.org_id,
      service: ei.service,
      instance: ei.instance,
      identifier: ei.identifier,
      owner:
        fragment(
          "CASE WHEN ? IS NOT NULL THEN 'device' WHEN ? IS NOT NULL THEN 'org_user' ELSE 'org' END",
          ei.device_id,
          ei.org_user_id
        ),
      device_id: ei.device_id,
      device_identifier: d.identifier,
      org_user_id: ei.org_user_id,
      user_id: ou.user_id,
      device_deleted_at: d.deleted_at,
      org_user_deleted_at: ou.deleted_at
    })
    |> Repo.fetch()
    |> case do
      {:ok, %{device_deleted_at: nil, org_user_deleted_at: nil} = found} ->
        {:ok, Map.drop(found, [:device_deleted_at, :org_user_deleted_at])}

      {:ok, _removed} ->
        {:error, :owner_deleted}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Record an identity a device has reported about itself.

  The device has proven this key on its own connection, so this is the trusted
  path — but proving a key says nothing about who registered it first, which is
  where the interesting cases are.

  Returns `{:error, :unsupported_service}` for a service this NervesHub does not
  know about. A device is free to run something we have no schema for, and that
  must not disturb its connection — the caller is expected to skip it.

  Returns `{:error, :claimed_elsewhere}` when the key is already held by another
  device, by a membership, or by another organisation. Nothing is changed, and
  it is logged as a warning: a key in two places is either a cloned image or
  somebody registering a key they do not own, and both want a person to look.

  Returns `{:error, :operator_managed}` when an operator recorded a *different*
  key for this device, service and instance. That disagreement means the device
  was reflashed, its state partition was wiped, or something is claiming to be
  it.

  A key an operator recorded by hand in this device's own organisation is
  **taken over** rather than refused: the row becomes device-owned. That is the
  intended flow for registering a device ahead of it appearing — put the key in,
  and the device claims it on its next connection.

  `attrs` may carry an `:instance` naming which endpoint of the service this is.
  A device running both an iroh console and an iroh application reports each
  under its own instance; anything that omits one is the service's only endpoint.
  """
  @spec report(pos_integer(), atom() | String.t(), map()) ::
          {:ok, NetworkIdentity.t()}
          | {:error,
             :unsupported_service
             | :operator_managed
             | :claimed_elsewhere
             | :device_not_found
             | Ecto.Changeset.t()}
  def report(device_id, service, attrs) do
    with {:ok, service} <- cast_service_result(service),
         {:ok, device} <- fetch_device(device_id) do
      do_report(device, service, attrs)
    end
  end

  defp cast_service_result(service) do
    case cast_service(service) do
      {:ok, service} -> {:ok, service}
      :error -> {:error, :unsupported_service}
    end
  end

  # The organisation is read from the device rather than passed in, so a caller
  # cannot record an identity into an organisation the device does not belong to.
  defp fetch_device(device_id) do
    Device
    |> where(id: ^device_id)
    |> where([d], is_nil(d.deleted_at))
    |> select([d], %{id: d.id, org_id: d.org_id})
    |> Repo.fetch(:device_not_found)
  end

  defp do_report(device, service, attrs) do
    identifier = attrs[:identifier] || attrs["identifier"]
    details = attrs[:details] || attrs["details"] || %{}
    instance = cast_instance(attrs[:instance] || attrs["instance"])

    # A device that reports nothing usable goes straight to the changeset, which
    # is where "identifier is required" gets said. Looking it up first would ask
    # Ecto to compare against nil, which it refuses.
    if is_binary(identifier) and identifier != "" do
      claim_or_record(device, service, instance, identifier, details)
    else
      record_for_instance(device, service, instance, identifier, details)
    end
  end

  defp claim_or_record(device, service, instance, identifier, details) do
    # Who, if anyone, already holds this key. Checked before the device's own row
    # so that a conflict is reported as a conflict, rather than arriving later as
    # a unique violation that repeats on every reconnect.
    case Repo.get_by(NetworkIdentity, service: service, identifier: identifier) do
      nil ->
        record_for_instance(device, service, instance, identifier, details)

      %NetworkIdentity{device_id: device_id, instance: ^instance} = existing
      when device_id == :erlang.map_get(:id, device) ->
        # The device's own row for this endpoint. Ordinary re-report, or a
        # detail change.
        update_own(existing, identifier, details, device)

      %NetworkIdentity{device_id: device_id} when device_id == :erlang.map_get(:id, device) ->
        # The device already holds this key under a different endpoint. One key
        # names one endpoint, so this is the device misreporting rather than a
        # rotation, and quietly moving the other row would lose an endpoint.
        Logger.warning(
          "[NetworkIdentities] device #{device.id} reported a #{service} key it already holds " <>
            "under another instance; leaving both alone"
        )

        {:error, :claimed_elsewhere}

      %NetworkIdentity{device_id: nil, org_user_id: nil, org_id: org_id} = unclaimed
      when org_id == :erlang.map_get(:org_id, device) ->
        claim(unclaimed, device, instance, details)

      other ->
        Logger.warning(
          "[NetworkIdentities] device #{device.id} reported a #{service} key already held by " <>
            "#{describe_owner(other)}; leaving it alone"
        )

        {:error, :claimed_elsewhere}
    end
  end

  # No one holds the key. The device may still have a row for this endpoint —
  # a rotated key — in which case that row moves rather than a second appearing.
  defp record_for_instance(device, service, instance, identifier, details) do
    case get(device.id, service, instance) do
      {:error, :not_found} ->
        %NetworkIdentity{}
        |> NetworkIdentity.changeset(%{
          org_id: device.org_id,
          device_id: device.id,
          service: service,
          instance: instance,
          identifier: identifier,
          details: details,
          source: :device_reported,
          last_reported_at: DateTime.utc_now()
        })
        |> Repo.insert()
        |> broadcast_if_ok(device.id)

      {:ok, %NetworkIdentity{source: :operator} = existing} ->
        Logger.warning(
          "[NetworkIdentities] device #{device.id} reported a #{service}/#{instance} identity " <>
            "that differs from the operator-recorded one; ignoring the device's value"
        )

        _ = existing
        {:error, :operator_managed}

      {:ok, existing} ->
        update(existing, identifier, details, device.id)
    end
  end

  # An operator recorded this key by hand and the device has now proven it, so
  # the row becomes the device's. Any row the device held for the same endpoint
  # is removed in the same transaction, since one owner has one identity per
  # endpoint and the partial unique index would refuse the second.
  defp claim(unclaimed, device, instance, details) do
    superseded =
      NetworkIdentity
      |> where(device_id: ^device.id)
      |> where(service: ^unclaimed.service)
      |> where(instance: ^instance)

    Multi.new()
    |> Multi.delete_all(:superseded, superseded)
    |> Multi.update(
      :claimed,
      NetworkIdentity.changeset(unclaimed, %{
        device_id: device.id,
        instance: instance,
        details: details,
        source: :device_reported,
        last_reported_at: DateTime.utc_now()
      })
    )
    |> Repo.transact()
    |> case do
      {:ok, %{claimed: claimed}} ->
        Logger.info(
          "[NetworkIdentities] device #{device.id} claimed a #{unclaimed.service} key " <>
            "that had been registered by hand"
        )

        broadcast_if_ok({:ok, claimed}, device.id)

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  defp update_own(%NetworkIdentity{source: :operator} = existing, identifier, _details, device) do
    if existing.identifier == identifier do
      # The device agrees with what the operator recorded, so record that we
      # heard from it and leave the row otherwise untouched.
      touch(existing)
    else
      Logger.warning(
        "[NetworkIdentities] device #{device.id} reported a #{existing.service} identity " <>
          "that differs from the operator-recorded one; ignoring the device's value"
      )

      {:error, :operator_managed}
    end
  end

  defp update_own(existing, identifier, details, device) do
    update(existing, identifier, details, device.id)
  end

  defp describe_owner(%NetworkIdentity{device_id: id}) when not is_nil(id), do: "device #{id}"

  defp describe_owner(%NetworkIdentity{org_user_id: id}) when not is_nil(id), do: "membership #{id}"

  defp describe_owner(%NetworkIdentity{org_id: id}), do: "organisation #{id} by hand"

  # An absent or unusable instance means "this service's only endpoint". Devices
  # that run one of something shouldn't have to say so.
  defp cast_instance(instance) when is_binary(instance) do
    case String.trim(instance) do
      "" -> NetworkIdentity.default_instance()
      trimmed -> trimmed
    end
  end

  defp cast_instance(instance) when is_atom(instance) and not is_nil(instance), do: Atom.to_string(instance)

  defp cast_instance(_instance), do: NetworkIdentity.default_instance()

  defp update(existing, identifier, details, device_id) do
    changed? = existing.identifier != identifier or existing.details != details

    existing
    |> NetworkIdentity.changeset(%{
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

  defp touch(%NetworkIdentity{} = identity) do
    identity
    |> NetworkIdentity.changeset(%{last_reported_at: DateTime.utc_now()})
    |> Repo.update()
  end

  defp broadcast_if_ok({:ok, identity} = result, device_id) do
    :ok = PubSub.broadcast(device_id, "network_identities:updated", %{service: identity.service})
    result
  end

  defp broadcast_if_ok(result, _device_id), do: result

  @doc """
  The atom this schema uses for a service name, or `:error`.

  Public because a caller taking a service from a query string has to know
  whether it names one before filtering on it. Ecto raises on an unknown value,
  and treating one as "no filter" would answer a typo with everything — which
  reads as a device holding identities it does not have.
  """
  @spec cast_service(atom() | String.t()) :: {:ok, atom()} | :error
  def cast_service(service)

  def cast_service(service) when is_atom(service) do
    if service in NetworkIdentity.services(), do: {:ok, service}, else: :error
  end

  def cast_service(service) when is_binary(service) do
    # String.to_existing_atom/1 is not enough on its own — every service name is
    # already an existing atom, so it would happily return one we do not support.
    Enum.find_value(NetworkIdentity.services(), :error, fn known ->
      if Atom.to_string(known) == service, do: {:ok, known}
    end)
  end

  def cast_service(_service), do: :error
end
