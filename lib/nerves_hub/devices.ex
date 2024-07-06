defmodule NervesHub.Devices do
  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi
  alias NervesHub.Accounts
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgKey
  alias NervesHub.AuditLogs
  alias NervesHub.Certificate
  alias NervesHub.Deployments
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Deployments.Orchestrator
  alias NervesHub.Devices.CACertificate
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceCertificate
  alias NervesHub.Devices.SharedSecretAuth
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Devices.UpdatePayload
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareMetadata
  alias NervesHub.Products
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias NervesHub.TaskSupervisor, as: Tasks

  @min_fwup_delta_updatable_version ">=1.10.0"

  def get_device!(device_id) do
    Repo.get!(Device, device_id)
  end

  def get_device(device_id) when is_integer(device_id) do
    Repo.get(Device, device_id)
  end

  def get_active_device(filters) do
    Device
    |> Repo.exclude_deleted()
    |> Repo.get_by(filters)
    |> case do
      nil -> {:error, :not_found}
      device -> {:ok, device}
    end
  end

  def get_devices_by_org_id(org_id) do
    query =
      from(
        d in Device,
        where: d.org_id == ^org_id
      )

    query
    |> Repo.exclude_deleted()
    |> order_by(asc: :identifier)
    |> Repo.all()
  end

  def get_devices_by_org_id_and_product_id(org_id, product_id) do
    query =
      from(
        d in Device,
        where: d.org_id == ^org_id,
        where: d.product_id == ^product_id
      )

    query
    |> Repo.exclude_deleted()
    |> Repo.all()
  end

  def get_devices_by_org_id_and_product_id(org_id, product_id, opts) do
    query =
      from(
        d in Device,
        where: d.org_id == ^org_id,
        where: d.product_id == ^product_id
      )

    pagination = Map.get(opts, :pagination, %{})
    sorting = Map.get(opts, :sort, {:asc, :identifier})
    filters = Map.get(opts, :filters, %{})

    query
    |> Repo.exclude_deleted()
    |> order_by(^sort_devices(sorting))
    |> filtering(filters)
    |> preload([:org, :product, deployment: [:firmware]])
    |> Repo.paginate(pagination)
  end

  defp sort_devices({:asc, :last_communication}), do: {:asc_nulls_first, :last_communication}

  defp sort_devices({:desc, :last_communication}), do: {:desc_nulls_last, :last_communication}

  defp sort_devices(sort), do: sort

  defp filtering(query, filters) do
    Enum.reduce(filters, query, fn {key, value}, query ->
      case {key, value} do
        {_, ""} ->
          query

        {"_target", _} ->
          query

        {"connection", _value} ->
          # TODO make this something in the database that we can query against
          # where(query, [d], d.connection == ^value)
          query

        {"connection_type", value} ->
          where(query, [d], ^value in d.connection_types)

        {"firmware_version", value} ->
          where(query, [d], d.firmware_metadata["version"] == ^value)

        {"platform", value} ->
          where(query, [d], d.firmware_metadata["platform"] == ^value)

        {"updates", "enabled"} ->
          where(query, [d], d.updates_enabled == true)

        {"updates", "penalty-box"} ->
          where(query, [d], d.updates_blocked_until > fragment("now() at time zone 'utc'"))

        {"updates", "disabled"} ->
          where(query, [d], d.updates_enabled == false)

        {"device_id", value} ->
          where(query, [d], ilike(d.identifier, ^"#{value}%"))

        {"tag", value} ->
          case NervesHub.Types.Tag.cast(value) do
            {:ok, tags} ->
              # This query here joins the table back to itself to unnest `tags` in a
              # way that is ILIKE-able. It's ugly but it works.
              query =
                query
                |> join(
                  :inner_lateral,
                  [d],
                  t in fragment("select unnest(tags) as tags from devices where id = ?", d.id),
                  on: true
                )
                |> group_by([d], d.id)

              Enum.reduce(tags, query, fn tag, query ->
                where(query, [d, t], ilike(t.tags, ^"#{tag}%"))
              end)

            {:error, _} ->
              query
          end
      end
    end)
  end

  def get_device_count_by_org_id(org_id) do
    q =
      from(
        d in Device,
        where: d.org_id == ^org_id,
        select: count(d)
      )

    q
    |> Repo.exclude_deleted()
    |> Repo.one!()
  end

  def get_device_count_by_product_id(product_id) do
    Device
    |> where([d], d.product_id == ^product_id)
    |> Repo.exclude_deleted()
    |> select([d], count(d))
    |> Repo.one!()
  end

  defp device_by_org_query(org_id, device_id) do
    from(
      d in Device,
      where: d.org_id == ^org_id,
      where: d.id == ^device_id
    )
  end

  defp device_by_product_query(device_id, product_id, org_id) do
    from(
      d in Device,
      where: d.org_id == ^org_id,
      where: d.id == ^device_id,
      where: d.product_id == ^product_id
    )
  end

  def get_device_by_product(device_id, product_id, org_id) do
    device_by_product_query(device_id, product_id, org_id)
    |> preload([:deployment])
    |> Repo.one!()
  end

  def get_device_by_org(%Org{id: org_id}, device_id) do
    device_by_org_query(org_id, device_id)
    |> Repo.exclude_deleted()
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      device -> {:ok, device}
    end
  end

  def get_device_by_org!(%Org{id: org_id}, device_id) do
    device_by_org_query(org_id, device_id)
    |> Repo.exclude_deleted()
    |> Repo.one!()
  end

  def get_by_identifier(identifier) do
    case Repo.get_by(Device, identifier: identifier) do
      nil ->
        {:error, :not_found}

      device ->
        {:ok, Repo.preload(device, [:org, :product, deployment: [:firmware]])}
    end
  end

  @spec get_device_by_identifier(Org.t(), String.t()) :: {:ok, Device.t()} | {:error, :not_found}
  def get_device_by_identifier(%Org{id: org_id}, identifier) when is_binary(identifier) do
    query =
      from(
        d in Device,
        where: d.identifier == ^identifier and d.org_id == ^org_id,
        preload: [:device_certificates, :deployment]
      )

    query
    |> Device.with_org()
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      device -> {:ok, device}
    end
  end

  @spec get_shared_secret_auth(String.t()) ::
          {:ok, SharedSecretAuth.t()} | {:error, :not_found}
  def get_shared_secret_auth(key) do
    SharedSecretAuth
    |> join(:inner, [ssa], d in assoc(ssa, :device))
    |> where([ssa], ssa.key == ^key)
    |> where([ssa], is_nil(ssa.deactivated_at))
    |> where([_, d], is_nil(d.deleted_at))
    |> preload([:device, :product_shared_secret_auth])
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      auth -> {:ok, auth}
    end
  end

  @spec create_shared_secret_auth(Device.t(), %{product_shared_secret_auth_id: pos_integer()}) ::
          {:ok, SharedSecretAuth.t()} | {:error, Changeset.t()}
  def create_shared_secret_auth(device, attrs \\ %{}) do
    device
    |> SharedSecretAuth.create_changeset(attrs)
    |> Repo.insert()
  end

  @spec get_or_create_device(Products.SharedSecretAuth.t(), String.t()) ::
          {:ok, Device.t()} | {:error, :not_found}
  def get_or_create_device(%Products.SharedSecretAuth{} = auth, identifier) do
    with {:error, :not_found} <-
           get_active_device(product_id: auth.product_id, identifier: identifier),
         {:ok, product} <-
           Products.get_product(auth.product_id) do
      create_device(%{
        org_id: product.org_id,
        product_id: product.id,
        identifier: identifier
      })
    else
      result ->
        result
    end
  end

  def get_device_by(filters) do
    Repo.get_by(Device, filters)
    |> case do
      nil -> {:error, :not_found}
      device -> {:ok, device}
    end
  end

  def get_eligible_deployments(%Device{firmware_metadata: nil}), do: []

  def get_eligible_deployments(%Device{firmware_metadata: meta} = device) do
    from(
      d in Deployment,
      join: p in assoc(d, :product),
      on: [org_id: ^device.org_id, name: ^meta.product],
      join: f in assoc(d, :firmware),
      on: f.product_id == p.id,
      where: d.is_active,
      where: d.healthy,
      where: f.architecture == ^meta.architecture,
      where: f.platform == ^meta.platform,
      where: f.uuid != ^meta.uuid,
      preload: [firmware: f]
    )
    |> Repo.all()
    |> Enum.filter(fn dep -> matches_deployment?(device, dep) end)
  end

  def get_eligible_deployments(_), do: []

  @spec create_device(map) :: {:ok, Device.t()} | {:error, Changeset.t()}
  def create_device(params) do
    %Device{}
    |> Device.changeset(params)
    |> Repo.insert()
  end

  def delete_device(%Device{} = device) do
    device_certificates_query = from(dc in DeviceCertificate, where: dc.device_id == ^device.id)
    changeset = Repo.soft_delete_changeset(device)

    Multi.new()
    |> Multi.delete_all(:device_certificates, device_certificates_query)
    |> Multi.update(:device, changeset)
    |> Repo.transaction()
    |> case do
      {:ok, %{device: device}} -> {:ok, device}
      error -> error
    end
  end

  @spec create_device_certificate(Device.t(), map() | X509.Certificate.t()) ::
          {:ok, DeviceCertificate.t()}
          | {:error, Changeset.t()}
  def create_device_certificate(%Device{} = device, otp_cert) when is_tuple(otp_cert) do
    {nb, na} = Certificate.get_validity(otp_cert)

    params = %{
      aki: Certificate.get_aki(otp_cert),
      der: Certificate.to_der(otp_cert),
      not_after: na,
      not_before: nb,
      serial: Certificate.get_serial_number(otp_cert),
      ski: Certificate.get_ski(otp_cert)
    }

    create_device_certificate(device, params)
  end

  def create_device_certificate(%Device{} = device, params) do
    params = Map.put(params, :org_id, device.org_id)

    changeset =
      device
      |> Ecto.build_assoc(:device_certificates)
      |> DeviceCertificate.changeset(params)

    case Repo.insert(changeset) do
      {:ok, device_certificate} ->
        :telemetry.execute([:nerves_hub, :device_certificates, :created], %{count: 1})

        {:ok, device_certificate}

      {:error, error} ->
        {:error, error}
    end
  end

  def get_device_certificates(%Device{} = device) do
    query =
      from(
        c in DeviceCertificate,
        join: d in assoc(c, :device),
        where: d.id == ^device.id
      )

    Repo.all(query)
  end

  @spec get_device_by_certificate(DeviceCertificate.t()) ::
          {:ok, Device.t()} | {:error, :not_found}
  def get_device_by_certificate(%DeviceCertificate{device: %Ecto.Association.NotLoaded{}} = cert) do
    Repo.preload(cert, :device)
    |> get_device_by_certificate()
  end

  def get_device_by_certificate(%DeviceCertificate{device: %Device{} = device}),
    do: {:ok, Repo.preload(device, :org)}

  def get_device_by_certificate(_), do: {:error, :not_found}

  def get_device_certificate_by_x509(cert) do
    fingerprint = NervesHub.Certificate.fingerprint(cert)

    from(DeviceCertificate, where: [fingerprint: ^fingerprint], preload: :device)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      certificate -> {:ok, certificate}
    end
  end

  def get_device_certificates_by_public_key(otp_cert) do
    pk_fingerprint = NervesHub.Certificate.public_key_fingerprint(otp_cert)

    from(c in DeviceCertificate,
      where: [public_key_fingerprint: ^pk_fingerprint],
      preload: [:device]
    )
    |> Repo.all()
  end

  @spec get_device_certificate_by_device_and_serial(Device.t(), binary) ::
          {:ok, DeviceCertificate.t()} | {:error, any()}
  def get_device_certificate_by_device_and_serial(%Device{id: device_id}, serial) do
    query =
      from(
        dc in DeviceCertificate,
        where: dc.serial == ^serial and dc.device_id == ^device_id
      )

    query
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      device_certificate ->
        {:ok, device_certificate}
    end
  end

  def update_device_certificate(%DeviceCertificate{} = certificate, params) do
    certificate
    |> DeviceCertificate.update_changeset(params)
    |> Repo.update()
  end

  @spec delete_device_certificate(DeviceCertificate.t()) ::
          {:ok, DeviceCertificate.t()}
          | {:error, Changeset.t()}
  def delete_device_certificate(%DeviceCertificate{} = device_certificate) do
    Repo.delete(device_certificate)
  end

  @spec create_ca_certificate(Org.t(), map()) ::
          {:ok, CACertificate.t()}
          | {:error, Changeset.t()}
  def create_ca_certificate(%Org{} = org, params) do
    org
    |> Ecto.build_assoc(:ca_certificates)
    |> CACertificate.changeset(params)
    |> Repo.insert()
    |> case do
      {:ok, ca_certificate} ->
        {:ok, Repo.preload(ca_certificate, jitp: :product)}

      err ->
        err
    end
  end

  @spec create_ca_certificate_from_x509(Org.t(), X509.Certificate.t(), binary() | nil) ::
          {:ok, CACertificate.t()} | {:error, Ecto.Changeset.t()}
  def create_ca_certificate_from_x509(%Org{} = org, otp_cert, description \\ nil)
      when is_tuple(otp_cert) do
    {not_before, not_after} = Certificate.get_validity(otp_cert)

    params = %{
      serial: Certificate.get_serial_number(otp_cert),
      aki: Certificate.get_aki(otp_cert),
      ski: Certificate.get_ski(otp_cert),
      not_before: not_before,
      not_after: not_after,
      der: X509.Certificate.to_der(otp_cert),
      description: description
    }

    create_ca_certificate(org, params)
  end

  def get_ca_certificates(%Org{id: org_id}) do
    from(ca in CACertificate, where: ca.org_id == ^org_id, preload: [jitp: :product])
    |> Repo.all()
  end

  @spec get_ca_certificate_by_aki(binary) :: {:ok, CACertificate.t()} | {:error, any()}
  def get_ca_certificate_by_aki(aki) do
    q = from(CACertificate, where: [aki: ^aki], preload: [jitp: :product])

    case Repo.one(q) do
      nil -> {:error, :not_found}
      ca_cert -> {:ok, ca_cert}
    end
  end

  @spec get_ca_certificate_by_ski(binary) :: {:ok, CACertificate.t()} | {:error, any()}
  def get_ca_certificate_by_ski(ski) do
    q = from(CACertificate, where: [ski: ^ski], preload: [jitp: :product])

    case Repo.one(q) do
      nil -> {:error, :not_found}
      ca_cert -> {:ok, ca_cert}
    end
  end

  @spec get_ca_certificate_by_serial(binary) :: {:ok, CACertificate.t()} | {:error, any()}
  def get_ca_certificate_by_serial(serial) do
    q = from(CACertificate, where: [serial: ^serial], preload: [jitp: :product])

    case Repo.one(q) do
      nil -> {:error, :not_found}
      ca_cert -> {:ok, ca_cert}
    end
  end

  @spec get_ca_certificate_by_org_and_serial(Org.t(), binary) ::
          {:ok, CACertificate.t()} | {:error, any()}
  def get_ca_certificate_by_org_and_serial(%Org{id: org_id}, serial) do
    query =
      from(
        ca in CACertificate,
        where: ca.serial == ^serial and ca.org_id == ^org_id,
        preload: [jitp: :product]
      )

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      ca_cert ->
        {:ok, ca_cert}
    end
  end

  def update_ca_certificate(%CACertificate{} = certificate, params) do
    certificate
    |> CACertificate.update_changeset(params)
    |> Repo.update()
  end

  def delete_ca_certificate(%CACertificate{} = ca_certificate) do
    Repo.delete(ca_certificate)
  end

  def device_connected(device) do
    update_device(device, %{last_communication: DateTime.utc_now()})
  end

  def update_firmware_metadata(device, nil) do
    {:ok, device}
  end

  def update_firmware_metadata(device, metadata) do
    description = "device #{device.identifier} updated firmware metadata"
    AuditLogs.audit!(device, device, description)
    update_device(device, %{firmware_metadata: metadata})
  end

  def update_device(%Device{} = device, params, opts \\ []) do
    changeset = Device.changeset(device, params)

    case Repo.update(changeset) do
      {:ok, device} ->
        case Map.has_key?(changeset.changes, :tags) do
          true ->
            description =
              "device #{device.identifier} tags changed, the attached deployment has been reset"

            AuditLogs.audit!(device, device, description)

            # Since the tags changed, let's find a new deployment
            device = %{device | deployment_id: nil, deployment: nil}
            device = Deployments.set_deployment(device)

            if Keyword.get(opts, :broadcast, true) do
              broadcast(device, "devices/updated")
            end

            {:ok, device}

          false ->
            if Keyword.get(opts, :broadcast, true) do
              broadcast(device, "devices/updated")
            end

            {:ok, device}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Resolve an update for the device's deployment
  """
  def resolve_update(%{deployment_id: nil}) do
    %UpdatePayload{update_available: false}
  end

  def resolve_update(device) do
    deployment = Repo.preload(device.deployment, [:firmware])

    case verify_update_eligibility(device, deployment) do
      {:ok, _device} ->
        {:ok, url} = Firmwares.get_firmware_url(deployment.firmware)
        {:ok, meta} = Firmwares.metadata_from_firmware(deployment.firmware)

        %UpdatePayload{
          update_available: true,
          firmware_url: url,
          firmware_meta: meta,
          deployment: deployment,
          deployment_id: deployment.id
        }

      {:error, :up_to_date, _device} ->
        %UpdatePayload{update_available: false}

      {:error, :updates_blocked, _device} ->
        %UpdatePayload{update_available: false}
    end
  end

  @spec delta_updatable?(
          source :: Firmware.t(),
          target :: Firmware.t(),
          Product.t(),
          fwup_version :: String.t()
        ) :: boolean()
  def delta_updatable?(nil, _target, _product, _fwup_version), do: false

  def delta_updatable?(source, target, product, fwup_version) do
    product.delta_updatable and
      target.delta_updatable and
      source.delta_updatable and
      Version.match?(fwup_version, @min_fwup_delta_updatable_version)
  end

  @doc """
  Verify that the deployment still matches the device

  This may clear the deployment from the device if the version or tags are different.
  """
  def verify_deployment(%{deployment_id: nil} = device) do
    device
  end

  def verify_deployment(device) do
    device = Repo.preload(device, [:deployment])

    case matches_deployment?(device, device.deployment) do
      true ->
        device

      false ->
        device
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_change(:deployment_id, nil)
        |> Repo.update!()
    end
  end

  @doc """
  Returns true if Version.match? and all deployment tags are in device tags.
  """
  def matches_deployment?(
        %Device{tags: tags, firmware_metadata: %FirmwareMetadata{version: version}},
        %Deployment{conditions: %{"version" => requirement, "tags" => dep_tags}}
      ) do
    if version_match?(version, requirement) and tags_match?(tags, dep_tags) do
      true
    else
      false
    end
  end

  def matches_deployment?(_, _), do: false

  @spec failure_threshold_met?(Device.t(), Deployment.t()) :: boolean()
  def failure_threshold_met?(%Device{} = device, %Deployment{} = deployment) do
    Enum.count(device.update_attempts) >= deployment.device_failure_threshold
  end

  @spec failure_rate_met?(Device.t(), Deployment.t()) :: boolean()
  def failure_rate_met?(%Device{} = device, %Deployment{} = deployment) do
    seconds_ago =
      Timex.shift(DateTime.utc_now(), seconds: -deployment.device_failure_rate_seconds)

    attempts =
      Enum.filter(device.update_attempts, fn attempt ->
        DateTime.compare(seconds_ago, attempt) == :lt
      end)

    Enum.count(attempts) >= deployment.device_failure_rate_amount
  end

  @doc """
  Devices that haven't been automatically blocked are not in the penalty window
  Devices that have a time greater than now are in the penalty window
  """
  def device_in_penalty_box?(device, now \\ DateTime.utc_now())

  def device_in_penalty_box?(%{updates_blocked_until: nil}, _now), do: false

  def device_in_penalty_box?(device, now) do
    DateTime.compare(device.updates_blocked_until, now) == :gt
  end

  defp updates_blocked?(device, now) do
    device.updates_enabled == false || device_in_penalty_box?(device, now)
  end

  def device_matches_deployment?(device, deployment) do
    device.firmware_metadata.uuid == deployment.firmware.uuid
  end

  def verify_update_eligibility(device, deployment, now \\ DateTime.utc_now()) do
    cond do
      device_matches_deployment?(device, deployment) ->
        {:error, :up_to_date, device}

      updates_blocked?(device, now) ->
        {:error, :updates_blocked, device}

      failure_rate_met?(device, deployment) ->
        blocked_until =
          DateTime.utc_now()
          |> DateTime.truncate(:second)
          |> DateTime.add(deployment.penalty_timeout_minutes * 60, :second)

        description = """
        Device #{device.identifier} automatically blocked firmware upgrades for #{deployment.penalty_timeout_minutes} minutes.
        Device failure rate met for firmware #{deployment.firmware.uuid} in deployment #{deployment.name}.
        """

        AuditLogs.audit!(deployment, device, description)

        {:ok, device} = update_device(device, %{updates_blocked_until: blocked_until})

        {:error, :updates_blocked, device}

      failure_threshold_met?(device, deployment) ->
        blocked_until =
          DateTime.utc_now()
          |> DateTime.truncate(:second)
          |> DateTime.add(deployment.penalty_timeout_minutes * 60, :second)

        description = """
        Device #{device.identifier} automatically blocked firmware upgrades for #{deployment.penalty_timeout_minutes} minutes.
        Device failure thredhold met for firmware #{deployment.firmware.uuid} in deployment #{deployment.name}.
        """

        AuditLogs.audit!(deployment, device, description)

        {:ok, device} = update_device(device, %{updates_blocked_until: blocked_until})

        {:error, :updates_blocked, device}

      true ->
        {:ok, device}
    end
  end

  def update_attempted(device, now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)

    changeset =
      device
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_change(:update_attempts, [now | device.update_attempts])

    Multi.new()
    |> Multi.update(:device, changeset)
    |> Multi.run(:audit_device, fn _, _ ->
      description = "device #{device.identifier} is attempting to update"
      AuditLogs.audit(device, device, description)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{device: device}} ->
        {:ok, device}

      err ->
        err
    end
  end

  def firmware_update_successful(device) do
    :telemetry.execute([:nerves_hub, :devices, :update, :successful], %{count: 1}, %{
      identifier: device.identifier,
      firmware_uuid: device.firmware_metadata.uuid
    })

    description =
      "device #{device.identifier} firmware set to version #{device.firmware_metadata.version} (#{device.firmware_metadata.uuid})"

    AuditLogs.audit!(device, device, description)

    # Clear the inflight update, no longer inflight!
    inflight_update =
      Repo.get_by(InflightUpdate,
        device_id: device.id,
        firmware_uuid: device.firmware_metadata.uuid
      )

    if inflight_update != nil do
      Orchestrator.device_updated(inflight_update.deployment_id)

      Deployment
      |> where([d], d.id == ^inflight_update.deployment_id)
      |> Repo.update_all(inc: [current_updated_devices: 1])

      Repo.delete(inflight_update)
    end

    device
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_change(:update_attempts, [])
    |> Ecto.Changeset.put_change(:updates_blocked_until, nil)
    |> Repo.update()
  end

  def restore_device(%Device{} = device) do
    update_device(device, %{deleted_at: nil})
  end

  @doc """
  Move a device to a different product

  If the new target product is in a different organization, this will
  attempt to also copy any signing keys the device might be expecting
  to the new organization. However, it is best effort only.

  Moving a device will also trigger a deployment check to see if there
  is an update available from the new product/org for the device. It is
  up to the user to ensure the new device is configured with any new/different
  signing keys from the new org before moving otherwise the device
  might fail to update because of an unknown key.
  """
  @spec move(Device.t() | [Device.t()], Product.t(), User.t()) :: Repo.transaction()
  def move(%Device{} = device, product, user) do
    product = Repo.preload(product, :org)

    attrs = %{
      org_id: product.org_id,
      product_id: product.id,
      deployment_id: nil
    }

    _ = maybe_copy_firmware_keys(device, product.org)

    description =
      "user #{user.name} moved device #{device.identifier} to #{product.org.name} : #{product.name}"

    source_product = %Product{
      id: device.product_id,
      org_id: device.org_id
    }

    Multi.new()
    |> Multi.run(:move, fn _, _ -> update_device(device, attrs) end)
    |> Multi.run(:audit_device, fn _, _ ->
      AuditLogs.audit(user, device, description)
    end)
    |> Multi.run(:audit_target, fn _, _ ->
      AuditLogs.audit(user, product, description)
    end)
    |> Multi.run(:audit_source, fn _, _ ->
      AuditLogs.audit(user, source_product, description)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{move: updated}} ->
        broadcast(updated, "moved")
        {:ok, updated}

      err ->
        err
    end
  end

  @spec tag_device(Device.t() | [Device.t()], User.t(), List.t()) :: Repo.transaction()
  def tag_device(%Device{} = device, user, tags) do
    description = "user #{user.name} updated device #{device.identifier} tags"
    params = %{tags: tags}
    update_device_with_audit(device, params, user, description)
  end

  @spec update_device_with_audit(Device.t(), Map.t(), User.t(), Map.t()) :: Repo.transaction()
  def update_device_with_audit(device, params, user, description) do
    Multi.new()
    |> Multi.run(:update_with_audit, fn _, _ ->
      update_device(device, params, broadcast: false)
    end)
    |> Multi.run(:audit_device, fn _, _ ->
      AuditLogs.audit(user, device, description)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{update_with_audit: updated}} ->
        broadcast(device, "devices/updated")
        {:ok, updated}

      err ->
        err
    end
  end

  @spec enable_updates(Device.t() | [Device.t()], User.t()) :: Repo.transaction()
  def enable_updates(%Device{} = device, user) do
    description = "user #{user.name} enabled updates for device #{device.identifier}"
    params = %{updates_enabled: true, update_attempts: []}
    update_device_with_audit(device, params, user, description)
  end

  @spec disable_updates(Device.t() | [Device.t()], User.t()) :: Repo.transaction()
  def disable_updates(%Device{} = device, user) do
    description = "user #{user.name} disabled updates for device #{device.identifier}"
    params = %{updates_enabled: false}
    update_device_with_audit(device, params, user, description)
  end

  def toggle_health(device, user) do
    case device.updates_enabled do
      true ->
        disable_updates(device, user)

      false ->
        enable_updates(device, user)
    end
  end

  def clear_penalty_box(%Device{} = device, user) do
    description = "user #{user.name} removed device #{device.identifier} from the penalty box"
    params = %{updates_blocked_until: nil, update_attempts: []}
    update_device_with_audit(device, params, user, description)
  end

  @spec move_many([Device.t()], Product.t(), User.t()) :: %{
          ok: [Device.t()],
          error: [{Ecto.Multi.name(), any()}]
        }
  def move_many(devices, product, user) do
    product = Repo.preload(product, :org)

    Enum.map(devices, &Task.Supervisor.async(Tasks, __MODULE__, :move, [&1, product, user]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  @spec disable_updates([Device.t()], User.t()) :: %{
          ok: [Device.t()],
          error: [{Ecto.Multi.name(), any()}]
        }
  def disable_updates_for_devices(devices, user) do
    Enum.map(devices, &Task.Supervisor.async(Tasks, __MODULE__, :disable_updates, [&1, user]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  @spec tag_devices([Device.t()], User.t(), List.t()) :: %{
          ok: [Device.t()],
          error: [{Ecto.Multi.name(), any()}]
        }
  def tag_devices(devices, user, tags) do
    Enum.map(devices, &Task.Supervisor.async(Tasks, __MODULE__, :tag_device, [&1, user, tags]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  @spec enable_updates_for_devices([Device.t()], User.t()) :: %{
          ok: [Device.t()],
          error: [{Ecto.Multi.name(), any()}]
        }
  def enable_updates_for_devices(devices, user) do
    Enum.map(devices, &Task.Supervisor.async(Tasks, __MODULE__, :enable_updates, [&1, user]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  def clear_penalty_box_for_devices(devices, user) do
    Enum.map(devices, &Task.Supervisor.async(Tasks, __MODULE__, :clear_penalty_box, [&1, user]))
    |> Task.await_many(20_000)
    |> Enum.reduce(%{ok: [], error: []}, fn
      {:ok, updated}, acc -> %{acc | ok: [updated | acc.ok]}
      {:error, name, changeset, _}, acc -> %{acc | error: [{name, changeset} | acc.error]}
    end)
  end

  @spec get_devices_by_id([non_neg_integer()]) :: [Device.t()]
  def get_devices_by_id(ids) when is_list(ids) do
    from(d in Device, where: d.id in ^ids)
    |> Repo.all()
  end

  def broadcast(%Device{id: id}, event, payload \\ %{}) do
    Phoenix.PubSub.broadcast(
      NervesHub.PubSub,
      "device:#{id}",
      %Phoenix.Socket.Broadcast{event: event, payload: payload}
    )
  end

  defp version_match?(_vsn, ""), do: true

  defp version_match?(version, requirement) do
    Version.match?(version, requirement)
  end

  defp tags_match?(nil, deployment_tags), do: tags_match?([], deployment_tags)
  defp tags_match?(device_tags, nil), do: tags_match?(device_tags, [])

  defp tags_match?(device_tags, deployment_tags) do
    Enum.all?(deployment_tags, fn tag -> tag in device_tags end)
  end

  def maybe_copy_firmware_keys(%{firmware_metadata: %{uuid: uuid}, org_id: source}, %Org{
        id: target
      }) do
    existing_target_keys = from(k in OrgKey, where: [org_id: ^target], select: k.key)

    from(
      k in OrgKey,
      join: f in Firmware,
      on: [org_key_id: k.id],
      where: f.uuid == ^uuid and k.org_id == ^source,
      where: k.key not in subquery(existing_target_keys),
      select: %{name: k.name, key: k.key, org_id: type(^target, :integer)}
    )
    |> Repo.one()
    |> case do
      %{} = attrs -> Accounts.create_org_key(attrs)
      _ -> :ignore
    end
  end

  def maybe_copy_firmware_keys(_old, _updated), do: :ignore

  @doc """
  Get distinct device platforms based on the product
  """
  def platforms(product_id) do
    Device
    |> select([d], fragment("?->>'platform'", d.firmware_metadata))
    |> distinct(true)
    |> where([d], d.product_id == ^product_id)
    |> Repo.all()
  end

  @doc """
  Deployment orchestrator told a device to update
  """
  def told_to_update(device, deployment) do
    expires_at =
      DateTime.utc_now()
      |> DateTime.add(60 * deployment.inflight_update_expiration_minutes, :second)
      |> DateTime.truncate(:second)

    changeset =
      %InflightUpdate{}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_change(:device_id, device.id)
      |> Ecto.Changeset.put_change(:deployment_id, deployment.id)
      |> Ecto.Changeset.put_change(:firmware_id, deployment.firmware_id)
      |> Ecto.Changeset.put_change(:firmware_uuid, deployment.firmware.uuid)
      |> Ecto.Changeset.put_change(:expires_at, expires_at)
      |> Ecto.Changeset.unique_constraint(:deployment_id,
        name: :inflight_updates_device_id_deployment_id_index
      )

    case Repo.insert(changeset) do
      {:ok, inflight_update} ->
        {:ok, inflight_update}

      {:error, _changeset} ->
        # Device already has an inflight update, fetch it
        case Repo.get_by(InflightUpdate, device_id: device.id, deployment_id: deployment.id) do
          nil ->
            :error

          inflight_update ->
            {:ok, inflight_update}
        end
    end
  end

  def clear_inflight_update(device) do
    InflightUpdate
    |> where([iu], iu.device_id == ^device.id)
    |> Repo.delete_all()
  end

  def update_started!(inflight_update) do
    inflight_update
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_change(:status, "updating")
    |> Repo.update!()
  end

  def inflight_updates_for(%Deployment{} = deployment) do
    InflightUpdate
    |> where([iu], iu.deployment_id == ^deployment.id)
    |> preload([:device])
    |> Repo.all()
  end

  def count_inflight_updates_for(%Deployment{} = deployment) do
    InflightUpdate
    |> select([iu], count(iu))
    |> where([iu], iu.deployment_id == ^deployment.id)
    |> Repo.one()
  end

  @doc """
  Get the firmware status for a device

  "latest", "pending", or "updating"
  """
  def firmware_status(device) do
    device = Repo.preload(device, deployment: [:firmware])

    cond do
      is_nil(device.deployment_id) ->
        "latest"

      device.firmware_metadata.uuid == device.deployment.firmware.uuid ->
        "latest"

      !Enum.empty?(device.update_attempts) ->
        "updating"

      true ->
        "pending"
    end
  end
end
