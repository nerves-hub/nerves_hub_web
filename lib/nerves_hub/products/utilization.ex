defmodule NervesHub.Products.Utilization do
  @moduledoc """
  How much of NervesHub a product is using: a checklist of features, each
  judged from what the server can see of the product, its devices and its
  organization.

  The same report backs the Utilization tab of a product's settings and
  `GET /api/orgs/:org_name/products/:product_name/utilization`, which
  `nh checklist` prints.

  ## Items

  Every item has a `group`:

  - `:authentication` - how the product's devices prove who they are.
  - `:recommended` - features every product is better off using.
  - `:optional` - situational features, listed as a bonus and never scored.

  and a `status`:

  - `:done` - in use. This is the reward.
  - `:attention` - a warning about something that is set up: it is risky
    (a shared secret), or it is switched on and nothing has arrived that
    would be expected to.
  - `:todo` - not in use, or not all the way there. Never a warning: nobody
    is in trouble for a feature they haven't set up.
  - `:unavailable` - this instance can't offer it (no ClickHouse, no
    encryption key), so it isn't held against the product.

  The score counts the authentication and recommended items that are `:done`
  against those the instance can offer.

  ## What the server can't see

  Only what leaves a trace on the server is judged. Firmware configuration
  that never shows up here (the remote console, a client module, the download
  strategy, TLS session resumption) has no item.

  A device's certificate says nothing about where its private key lives, so
  NervesKey is recognised by the shape of the certificate the NervesKey
  tooling signs: a serial number and validity dates that fit the ATECC508A
  compressed certificate format. Any other
  certificate is counted as LocalCert, which therefore includes keys held in a
  TPM or anything else NervesHub has no way to tell apart.
  """

  import Ecto.Query

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgRole
  alias NervesHub.Accounts.TwoFactor
  alias NervesHub.Archives.Archive
  alias NervesHub.Devices.CACertificate.JITP
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceCertificate
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.DeviceLatestMetrics
  alias NervesHub.Devices.LogLines
  alias NervesHub.Devices.NetworkIdentity
  alias NervesHub.Devices.SharedSecretAuth, as: DeviceSharedSecretAuth
  alias NervesHub.ErrorReports.ErrorGroup
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Integrations
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Products.ApiKeys
  alias NervesHub.Products.HealthProfiles
  alias NervesHub.Products.Product
  alias NervesHub.Products.SharedSecretAuth
  alias NervesHub.Repo
  alias NervesHub.Scripts.Script

  @docs "https://docs.nerves-hub.org"

  @type status :: :done | :attention | :todo | :unavailable
  @type group :: :authentication | :recommended | :optional

  @type item :: %{
          key: String.t(),
          group: group(),
          title: String.t(),
          description: String.t(),
          status: status(),
          summary: String.t(),
          docs_url: String.t()
        }

  @type auth_method :: %{
          key: String.t(),
          label: String.t(),
          level: :good | :warning,
          devices: non_neg_integer()
        }

  @type score :: %{done: non_neg_integer(), total: non_neg_integer()}

  @type t :: %{score: score(), device_auth: [auth_method()], items: [item()]}

  # {key, group, title, description, docs path}. The order is the order shown.
  @items [
    {"device_auth", :authentication, "Device authentication",
     "Give each device its own certificate, with the key in a NervesKey or TPM where the hardware has one. A secret shared by the whole product is one credential for every device, meant for getting started; a device with a secret of its own is fine.",
     "/auth/device-certificates"},
    {"signed_firmware", :recommended, "Signed firmware",
     "Sign firmware with one of the organization's signing keys and upload it, so devices only install what you built.",
     "/concepts/firmware-signing"},
    {"deployments", :recommended, "Deployment groups",
     "Send firmware through a deployment group that is turned on and has a release, rather than device by device.",
     "/setup/deployments"},
    {"delta_updates", :recommended, "Delta updates",
     "Send only what changed between two firmware versions. The firmware has to declare delta sources in fwup.conf, and the deployment group has to have delta updates on.",
     "/management/delta-updates"},
    {"client_library", :recommended, "Current client library",
     "Run a client that names itself and its version when it connects, which NervesHubLink does from 2.14.0. Older clients miss logging, error reports and the refusal of unverified updates.",
     "/integrations/nerves-hub-link"},
    {"health", :recommended, "Health reports",
     "Have devices report metrics, metadata and alarms through the Health extension, so the fleet's health shows on the devices list and Insights.",
     "/extensions/health"},
    {"geo", :recommended, "Device location",
     "Have devices report where they are through the Geo extension, by GeoIP or a resolver of your own.",
     "/extensions/geo"},
    {"logging", :recommended, "Device logs",
     "Have devices send their logs through the Logging extension, so they can be read and searched without a console session.",
     "/extensions/logging"},
    {"error_reports", :recommended, "Error reports",
     "Have devices report exceptions and crashes through the Error Reports extension, grouped into issues on the product's Errors page.",
     "/extensions/error-reports"},
    {"firmware_validation", :recommended, "Firmware validation",
     "Have devices report whether new firmware was validated or reverted, so a failed update is known rather than guessed.",
     "/updates/applying-updates"},
    {"ci_api_key", :recommended, "Uploads from CI",
     "Give your build pipeline a product API key to upload and release firmware, instead of a person's token.",
     "/outbound/ci-cd"},
    {"notifications", :recommended, "Notifications to your team",
     "Send this product's events to Slack, Microsoft Teams, Discord or a webhook, so problems reach people without them watching the dashboard.",
     "/outbound/slack"},
    {"two_factor", :recommended, "Two-factor authentication required",
     "Require two-factor authentication of every member of the organization.", "/access/two-factor"},
    {"deployment_workflow", :optional, "Staged rollouts",
     "Roll a release out in steps, such as canaries and then an approval, with a deployment workflow.",
     "/concepts/deployment-workflows"},
    {"priority_queue", :optional, "Priority queue",
     "Let devices far behind on firmware jump the update queue in a deployment group.",
     "/deployments/rollout-controls"},
    {"archives", :optional, "Archives", "Ship signed files to devices alongside firmware, outside the firmware image.",
     "/updates/archives"},
    {"support_scripts", :optional, "Support scripts",
     "Keep the commands your team runs on devices as scripts, run from a device's page or the CLI.",
     "/management/support-scripts"},
    {"device_managed_updates", :optional, "Device-managed updates",
     "Let devices decide for themselves when to check for and take an update.", "/updates/device-managed-updates"},
    {"local_shell", :optional, "Local shell",
     "Open a system shell on a device, beside the IEx console, through the Local Shell extension.",
     "/extensions/local-shell"},
    {"network_identity", :optional, "Network identities",
     "Record each device's identity on networks NervesHub doesn't run, such as iroh, NetBird, Tailscale or WireGuard.",
     "/extensions/network-identity"},
    {"connecting_code", :optional, "Connecting code",
     "Run a snippet of code on a device each time it connects, set on a device, a deployment group or a release.",
     "/deployments/connecting-code"},
    {"jitp", :optional, "Just-in-time provisioning",
     "Create devices on first connect from a certificate authority you registered, instead of adding each one ahead of time.",
     "/auth/just-in-time-provisioning"},
    {"platform_health_profiles", :optional, "Health profiles per platform",
     "Give a platform its own health thresholds when one set doesn't fit every kind of hardware in the product.",
     "/management/health-monitoring"},
    {"custom_roles", :optional, "Custom roles",
     "Define roles of your own for the organization, such as an approver or a role limited to devices with certain tags.",
     "/access/roles"},
    {"other_firmware_formats", :optional, "Other firmware formats",
     "Accept RAUC bundles, ESP-IDF images or AtomVM archives for devices that don't run Nerves.", "/updates/overview"}
  ]

  @doc """
  The product's whole report: its score, how its devices authenticate, and
  every item in the order it is shown.
  """
  @spec report(Product.t()) :: t()
  def report(%Product{} = product) do
    facts = facts(product)
    items = Enum.map(@items, &item(&1, facts))

    %{score: score_items(items), device_auth: auth_methods(facts.devices), items: items}
  end

  @doc """
  Just the product's score, for the count on the Utilization tab.
  """
  @spec score(Product.t()) :: score()
  def score(%Product{} = product), do: report(product).score

  defp score_items(items) do
    scored = Enum.filter(items, &(&1.group != :optional and &1.status != :unavailable))

    %{done: Enum.count(scored, &(&1.status == :done)), total: length(scored)}
  end

  defp item({key, group, title, description, docs_path}, facts) do
    {status, summary} = judge(key, facts)

    %{
      key: key,
      group: group,
      title: title,
      description: description,
      status: status,
      summary: summary,
      docs_url: @docs <> docs_path
    }
  end

  defp auth_methods(devices) do
    [
      %{
        key: "shared_secret",
        label: "Shared Secret",
        level: if(devices.own_secret > 0 and devices.shared_secret == 0, do: :good, else: :warning),
        devices: devices.shared_secret + devices.own_secret
      },
      %{key: "local_cert", label: "LocalCert", level: :good, devices: devices.local_cert},
      %{key: "nerves_key", label: "NervesKey", level: :good, devices: devices.nerves_key}
    ]
  end

  ## Judging each item

  defp judge("device_auth", %{devices: devices, active_shared_secrets: secrets}) do
    certificates = devices.local_cert + devices.nerves_key
    authenticated = certificates + devices.shared_secret + devices.own_secret

    cond do
      authenticated == 0 ->
        {:todo, "No device has connected yet."}

      devices.shared_secret > 0 ->
        {:attention,
         "#{devices.shared_secret} of #{count(authenticated, "device")} #{if devices.shared_secret == 1, do: "connects", else: "connect"} with a secret shared by the whole product."}

      secrets > 0 and devices.own_secret == 0 ->
        {:attention,
         "Every device has a certificate, but #{count(secrets, "product shared secret")} can still be used to connect. Deactivate #{if secrets == 1, do: "it", else: "them"} to finish."}

      true ->
        {:done, authenticated_summary(certificates, devices.own_secret)}
    end
  end

  defp judge("signed_firmware", %{firmware: 0}), do: {:todo, "No firmware has been uploaded."}
  defp judge("signed_firmware", %{firmware: n}), do: {:done, "#{count(n, "signed firmware")} uploaded."}

  defp judge("deployments", %{groups: []}), do: {:todo, "There are no deployment groups."}

  defp judge("deployments", %{groups: groups}) do
    case Enum.count(groups, &(&1.active and &1.release)) do
      0 -> {:todo, "#{count(length(groups), "deployment group")}, none of them turned on with a release."}
      n -> {:done, "#{n} of #{count(length(groups), "deployment group")} turned on with a release."}
    end
  end

  defp judge("delta_updates", %{groups: groups}) do
    sending = Enum.filter(groups, &(&1.active and &1.release))
    wanting = Enum.filter(sending, & &1.delta)

    cond do
      sending == [] ->
        {:todo, "Needs a deployment group that is turned on with a release."}

      wanting == [] ->
        {:todo, "Delta updates are off for every deployment group that is turned on."}

      Enum.any?(wanting, & &1.firmware_delta) ->
        {:done, "#{count(Enum.count(wanting, & &1.firmware_delta), "deployment group")} sending delta updates."}

      true ->
        {:attention,
         "Delta updates are on, but the firmware being released declares no delta sources, so devices get it in full."}
    end
  end

  defp judge("client_library", %{connections: %{total: 0}}), do: {:todo, "No device has connected yet."}

  defp judge("client_library", %{connections: %{total: total, identified: total}}) do
    {:done, "#{all(total, "device")} that connected named its client library."}
  end

  defp judge("client_library", %{connections: %{total: total, identified: identified}}) do
    {:todo,
     "#{identified} of #{count(total, "device")} named a client library when last connecting. NervesHubLink before 2.14.0 doesn't."}
  end

  defp judge("health", facts) do
    extension(facts, :health, facts.health_reported?, "A device has reported its health.")
  end

  defp judge("geo", facts) do
    extension(facts, :geo, facts.location_reported?, "A device has reported its location.")
  end

  defp judge("logging", %{analytics?: false}), do: no_analytics()

  # Any running device logs something, so a product with logging on and no
  # log lines has devices that aren't sending them.
  defp judge("logging", facts) do
    case {switch(facts, :logging), facts.logs_stored?} do
      {{:done, _on}, true} -> {:done, "Devices are sending their logs."}
      {{:done, _on}, false} -> {:attention, "The extension is on, but no device has sent a log line."}
      {on_or_off, _unknown} -> on_or_off
    end
  end

  defp judge("error_reports", %{analytics?: false}), do: no_analytics()

  # No errors may only mean nothing has gone wrong, so the switch is enough.
  defp judge("error_reports", facts) do
    case {switch(facts, :error_reports), facts.error_groups} do
      {{:done, _on}, 0} ->
        {:done, "The extension is on. No device has reported an error, which is what a healthy fleet looks like."}

      {{:done, _on}, n} ->
        {:done, "#{count(n, "issue")} reported by devices."}

      {off, _groups} ->
        off
    end
  end

  defp judge("firmware_validation", %{devices: %{validated: 0}}) do
    {:todo, "No device has reported its firmware as validated."}
  end

  defp judge("firmware_validation", %{devices: %{validated: n}}) do
    {:done, "#{count(n, "device")} reported validated firmware."}
  end

  defp judge("ci_api_key", %{api_keys: 0}), do: {:todo, "The product has no active API key."}
  defp judge("ci_api_key", %{api_keys: n}), do: {:done, "#{count(n, "active API key")}."}

  defp judge("notifications", %{listeners: []}) do
    {:todo, "Nothing outside #{platform()} hears this product's events."}
  end

  defp judge("notifications", %{listeners: kinds}) do
    {:done, "Events go to #{kinds |> Enum.map(&listener_name/1) |> sentence()}."}
  end

  defp judge("two_factor", %{two_factor_available?: false, org: %{require_two_factor: false}}) do
    {:unavailable, "This server has no encryption key, which two-factor authentication needs."}
  end

  defp judge("two_factor", %{org: %{require_two_factor: true} = org}),
    do: {:done, "Required of everyone in #{org.name}."}

  defp judge("two_factor", %{org: org}), do: {:todo, "Members of #{org.name} can sign in without it."}

  defp judge("deployment_workflow", %{groups: groups}) do
    used(
      Enum.count(groups, & &1.workflow),
      "deployment group",
      "with a workflow",
      "No deployment group has a workflow."
    )
  end

  defp judge("priority_queue", %{groups: groups}) do
    used(
      Enum.count(groups, & &1.priority_queue),
      "deployment group",
      "with a priority queue",
      "No deployment group has a priority queue."
    )
  end

  defp judge("archives", %{archives: n}), do: used(n, "archive", "uploaded", "No archive has been uploaded.")
  defp judge("support_scripts", %{scripts: n}), do: used(n, "support script", "saved", "There are no support scripts.")

  defp judge("device_managed_updates", %{devices: %{device_managed: 0}, product: product}) do
    if product.default_managed_updates_allowed do
      {:done, "New devices are allowed to manage their own updates."}
    else
      {:todo, "No device manages its own updates."}
    end
  end

  defp judge("device_managed_updates", %{devices: %{device_managed: n}}) do
    {:done, "#{count(n, "device")} managing #{if n == 1, do: "its", else: "their"} own updates."}
  end

  defp judge("local_shell", facts), do: switch(facts, :local_shell)

  defp judge("network_identity", %{network_identities?: true}), do: {:done, "A device has a network identity."}

  defp judge("network_identity", %{network_identities?: false} = facts) do
    # The extension says nothing without a provider in firmware, so being
    # on is not a sign that anyone meant to use it.
    case switch(facts, :network_identity) do
      {:done, _summary} -> {:todo, "The extension is on, but no device has a network identity."}
      off -> off
    end
  end

  defp judge("connecting_code", %{devices: devices, groups: groups}) do
    in_groups = Enum.count(groups, & &1.connecting_code)

    cond do
      devices.connecting_code > 0 -> {:done, "#{count(devices.connecting_code, "device")} with connecting code."}
      in_groups > 0 -> {:done, "#{count(in_groups, "deployment group")} with connecting code."}
      true -> {:todo, "Nothing has connecting code."}
    end
  end

  defp judge("jitp", %{jitp?: true}), do: {:done, "A certificate authority creates devices in this product."}
  defp judge("jitp", %{jitp?: false}), do: {:todo, "No certificate authority creates devices in this product."}

  defp judge("platform_health_profiles", %{health_profiles: n}) when n > 1 do
    {:done, "#{count(n - 1, "platform")} with a health profile of its own."}
  end

  defp judge("platform_health_profiles", _facts), do: {:todo, "Every platform uses the default health profile."}

  defp judge("custom_roles", %{custom_roles: n, org: org}) do
    used(n, "custom role", "in #{org.name}", "#{org.name} has only the built-in roles.")
  end

  defp judge("other_firmware_formats", %{product: product}) do
    case product.allowed_update_tools -- ["fwup"] do
      [] -> {:todo, "The product accepts fwup firmware only."}
      tools -> {:done, "The product also accepts #{sentence(tools)}."}
    end
  end

  # An extension whose devices report on a schedule: on for the product, and
  # a device has reported. On with nothing arriving is worth a warning.
  defp extension(facts, key, reported?, reported) do
    case {switch(facts, key), reported?} do
      {{:done, _on}, true} -> {:done, reported}
      {{:done, _on}, false} -> {:attention, "The extension is on, but no device has reported yet."}
      {off, _reported?} -> off
    end
  end

  defp no_analytics() do
    {:unavailable, "This server has no ClickHouse, which this extension stores its data in."}
  end

  defp switch(%{product: product}, key) do
    if product.extensions && Map.get(product.extensions, key) do
      {:done, "The extension is on for this product."}
    else
      {:todo, "The extension is off for this product."}
    end
  end

  defp used(0, _noun, _doing, none), do: {:todo, none}
  defp used(n, noun, doing, _none), do: {:done, "#{count(n, noun)} #{doing}."}

  defp listener_name("slack"), do: "Slack"
  defp listener_name("chat_webhook"), do: "Teams or Discord"
  defp listener_name("webhook"), do: "a webhook"

  defp platform(), do: NervesHub.Branding.friendly_platform_name()

  defp count(1, noun), do: "1 #{noun}"
  defp count(n, "signed firmware"), do: "#{n} signed firmwares"
  defp count(n, noun), do: "#{n} #{noun}s"

  defp all(1, noun), do: "The 1 #{noun}"
  defp all(n, noun), do: "All #{n} #{noun}s"

  defp sentence([one]), do: one
  defp sentence([one, two]), do: "#{one} and #{two}"
  defp sentence(many), do: Enum.join(Enum.drop(many, -1), ", ") <> " and " <> List.last(many)

  defp authenticated_summary(certificates, 0), do: "#{all(certificates, "device")} with a certificate."
  defp authenticated_summary(0, own), do: "#{all(own, "device")} with #{own_secret(own)}."

  defp authenticated_summary(certificates, own) do
    "#{count(certificates, "device")} with a certificate, #{own} with #{own_secret(own)}."
  end

  defp own_secret(1), do: "a secret of its own"
  defp own_secret(_many), do: "a secret of their own"

  ## Facts

  # Everything the items are judged from. Each is one aggregate or existence
  # query, never a row per device, since every settings tab asks for the
  # score.
  defp facts(%Product{id: product_id} = product) do
    org = Repo.get!(Org, product.org_id)
    analytics? = Application.get_env(:nerves_hub, :analytics_enabled, false) == true

    %{
      product: product,
      org: org,
      analytics?: analytics?,
      logs_stored?: logs_stored?(product, analytics?),
      error_groups: count_where(ErrorGroup, product_id),
      two_factor_available?: TwoFactor.available?(),
      devices: devices(product_id),
      active_shared_secrets: count_where(SharedSecretAuth, product_id, &where(&1, [s], is_nil(s.deactivated_at))),
      firmware: count_where(Firmware, product_id, &where(&1, [f], is_nil(f.deleted_at))),
      groups: groups(product_id),
      connections: connections(product_id),
      health_reported?: Repo.exists?(where(DeviceLatestMetrics, product_id: ^product_id)),
      location_reported?: location_reported?(product_id),
      api_keys: ApiKeys.active_count(product),
      listeners: Integrations.kinds_hearing(product),
      archives: count_where(Archive, product_id),
      scripts: count_where(Script, product_id),
      network_identities?: network_identities?(product_id),
      jitp?: Repo.exists?(where(JITP, product_id: ^product_id)),
      health_profiles: HealthProfiles.count_for_product(product),
      custom_roles: Repo.aggregate(where(OrgRole, [r], r.org_id == ^org.id and is_nil(r.deleted_at)), :count)
    }
  end

  # Asked of ClickHouse only when the answer is used: the product has logging
  # on. `:unknown` when ClickHouse doesn't answer, which leaves the switch.
  defp logs_stored?(%Product{id: product_id, extensions: %{logging: true}}, true) do
    LogLines.any_for_product?(product_id)
  end

  defp logs_stored?(_product, _analytics?), do: :unknown

  defp count_where(schema, product_id, narrow \\ & &1) do
    schema
    |> where(product_id: ^product_id)
    |> narrow.()
    |> Repo.aggregate(:count)
  end

  # A device with a certificate connects with it. One without, that has
  # connected (`:provisioned`), can only have used a shared secret: its own
  # if it has one that is still active, and otherwise the product's. One
  # without that is still `:registered` hasn't shown how it will connect.
  #
  # A certificate counts as a NervesKey's when it is one the NervesKey tooling
  # would sign. An ATECC508A stores its certificate compressed, which only
  # works for a certificate built to fit: a 128-bit serial number whose top
  # two bits are `01` (so from 2^126 up to 2^127), and validity dates on the
  # hour. A certificate from `nh`, `mix nerves_hub.device cert create` or
  # OpenSSL has a random serial number and dates to the second, so it doesn't
  # fit by accident. It is a match on shape, not proof of where the key is.
  defp devices(product_id) do
    certificates =
      from(c in DeviceCertificate,
        join: d in Device,
        on: d.id == c.device_id,
        where: d.product_id == ^product_id and is_nil(d.deleted_at),
        group_by: c.device_id,
        select: %{
          device_id: c.device_id,
          nerves_key:
            fragment(
              """
              bool_or(CASE WHEN ? ~ '^[0-9]{38,39}$'
              THEN ?::numeric >= 85070591730234615865843651857942052864
               AND ?::numeric < 170141183460469231731687303715884105728
               AND date_trunc('hour', ?) = ?
               AND date_trunc('hour', ?) = ?
              ELSE false END)
              """,
              c.serial,
              c.serial,
              c.serial,
              c.not_before,
              c.not_before,
              c.not_after,
              c.not_after
            )
        }
      )

    own_secrets =
      from(s in DeviceSharedSecretAuth,
        where: is_nil(s.deactivated_at),
        distinct: true,
        select: %{device_id: s.device_id}
      )

    from(d in Device,
      left_join: c in subquery(certificates),
      on: c.device_id == d.id,
      left_join: s in subquery(own_secrets),
      on: s.device_id == d.id,
      where: d.product_id == ^product_id and is_nil(d.deleted_at),
      select: %{
        nerves_key: filter(count(), c.nerves_key == true),
        local_cert: filter(count(), c.nerves_key == false),
        shared_secret: filter(count(), is_nil(c.device_id) and is_nil(s.device_id) and d.status == :provisioned),
        own_secret: filter(count(), is_nil(c.device_id) and not is_nil(s.device_id) and d.status == :provisioned),
        validated: filter(count(), d.firmware_validation_status == :validated),
        device_managed: filter(count(), d.update_mode == :device_managed),
        connecting_code: filter(count(), not is_nil(d.connecting_code) and d.connecting_code != "")
      }
    )
    |> Repo.one!()
  end

  defp groups(product_id) do
    from(g in DeploymentGroup,
      left_join: r in assoc(g, :current_release),
      left_join: f in assoc(r, :firmware),
      where: g.product_id == ^product_id,
      select: %{
        active: g.is_active,
        release: not is_nil(r.id),
        delta: g.delta_updatable,
        firmware_delta: coalesce(f.delta_updatable, false),
        workflow: not is_nil(g.workflow_definition),
        priority_queue: g.priority_queue_enabled,
        connecting_code:
          (not is_nil(g.connecting_code) and g.connecting_code != "") or
            (not is_nil(r.connecting_code) and r.connecting_code != "")
      }
    )
    |> Repo.all()
  end

  # A device keeps one connection row, its latest, so this is each device's
  # last word on which client it runs.
  defp connections(product_id) do
    from(c in DeviceConnection,
      join: d in Device,
      on: d.id == c.device_id,
      where: c.product_id == ^product_id and is_nil(d.deleted_at),
      select: %{total: count(), identified: filter(count(), not is_nil(c.lib))}
    )
    |> Repo.one!()
  end

  defp location_reported?(product_id) do
    DeviceConnection
    |> where([c], c.product_id == ^product_id and fragment("jsonb_exists(?, 'location')", c.metadata))
    |> Repo.exists?()
  end

  defp network_identities?(product_id) do
    from(n in NetworkIdentity,
      join: d in Device,
      on: d.id == n.device_id,
      where: d.product_id == ^product_id and is_nil(d.deleted_at)
    )
    |> Repo.exists?()
  end
end
