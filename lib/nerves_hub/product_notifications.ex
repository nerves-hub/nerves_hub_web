defmodule NervesHub.ProductNotifications do
  import Ecto.Query

  alias NervesHub.Accounts.Scope
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Device
  alias NervesHub.Integrations
  alias NervesHub.Integrations.ChatWebhooks
  alias NervesHub.Integrations.ChatWebhooks.ChatWebhook
  alias NervesHub.Integrations.Slack.Subscription
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.ProductNotifications.Copy
  alias NervesHub.ProductNotifications.Subjects
  alias NervesHub.Products
  alias NervesHub.Products.Notification
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias NervesHub.Webhooks.Webhook
  alias Phoenix.Socket.Broadcast

  # Failure reasons arrive in a device's message payload, so they are whatever
  # the device chose to send. Cap them before they reach a notification the UI
  # renders, the way `DeviceTemplates` does for audit log descriptions.
  @reason_max_length 200

  @spec subscribe(pos_integer()) :: :ok
  def subscribe(product_id) do
    :ok = Group.join(NervesHub.Group, key(product_id), %{})
  end

  @levels [:error, :warning, :info]

  @typedoc """
  A card in the product's notifications list: one notification, or every
  device's notification of one kind rolled up together (see
  `Notification.device_kinds/0`). `key` is the notification's ID for one, and
  the kind for a roll-up. `latest` is the most recent notification in it, and
  `title` and `message` are written for the card by
  `NervesHub.ProductNotifications.Copy`.
  """
  @type card :: %{
          key: String.t(),
          kind: Notification.kind() | nil,
          level: Notification.level(),
          title: String.t(),
          message: String.t(),
          devices: pos_integer(),
          occurrences: pos_integer(),
          last_occurred_at: DateTime.t(),
          latest: Notification.t()
        }

  @doc """
  A page of the product's notifications list, the most recent card first,
  with the pagination it's on and when the card before the page last
  happened (`nil` on the first page), so a page that starts partway through a
  day can say so. A page past the end is the last page. Pass a `level` to
  list only the cards at that level.
  """
  @spec list_cards(Product.t(), pos_integer(), pos_integer(), Notification.level() | nil) ::
          {[card()], Flop.Meta.t(), DateTime.t() | nil}
  def list_cards(%Product{} = product, page \\ 1, page_size \\ 25, level \\ nil) do
    total = Repo.one(from(k in subquery(keyed(product, level)), select: count(k.key, :distinct)))
    total_pages = max(div(total + page_size - 1, page_size), 1)
    page = page |> max(1) |> min(total_pages)
    skip = (page - 1) * page_size

    # One more than the page, the card before it, unless it's the first.
    rows =
      from(k in subquery(keyed(product, level)),
        group_by: k.key,
        select: %{
          key: k.key,
          last_occurred_at: max(k.last_occurred_at),
          devices: count(k.key),
          occurrences: type(sum(k.occurrence_count), :integer)
        },
        order_by: [desc: max(k.last_occurred_at), desc: k.key],
        offset: ^max(skip - 1, 0),
        limit: ^(page_size + min(skip, 1))
      )
      |> Repo.all()

    {before, rows} = if skip > 0, do: Enum.split(rows, 1), else: {[], rows}

    meta = %Flop.Meta{
      current_page: page,
      page_size: page_size,
      total_count: total,
      total_pages: total_pages,
      has_previous_page?: page > 1,
      has_next_page?: page < total_pages
    }

    {cards(product, rows), meta, Enum.at(before, 0)[:last_occurred_at]}
  end

  # Each of the product's notifications with the card it's on: its kind if
  # that's rolled up, otherwise its own ID.
  defp keyed(product, level) do
    rolled_up = Enum.map(Notification.device_kinds(), &Atom.to_string/1)

    from(n in listed(product, level),
      select: %{
        key:
          fragment(
            "CASE WHEN ? = ANY(?) THEN ? ELSE ?::text END",
            n.kind,
            type(^rolled_up, {:array, :string}),
            n.kind,
            n.id
          ),
        level: n.level,
        last_occurred_at: n.last_occurred_at,
        occurrence_count: n.occurrence_count
      }
    )
  end

  defp listed(product, nil), do: where(Notification, [n], n.product_id == ^product.id)

  defp listed(product, level) when level in @levels,
    do: where(Notification, [n], n.product_id == ^product.id and n.level == ^level)

  # The most recent notification on each card, for its kind, level and copy.
  defp cards(_product, []), do: []

  defp cards(product, rows) do
    kinds = Map.new(Notification.device_kinds(), &{Atom.to_string(&1), &1})
    {rolled_up, single} = Enum.split_with(rows, &Map.has_key?(kinds, &1.key))

    singles =
      Notification
      |> where([n], n.product_id == ^product.id and n.id in ^Enum.map(single, & &1.key))
      |> Repo.all()

    latest_of_kinds =
      Notification
      |> where([n], n.product_id == ^product.id and n.kind in ^Enum.map(rolled_up, &Map.fetch!(kinds, &1.key)))
      |> distinct([n], n.kind)
      |> order_by([n], desc: n.last_occurred_at, desc: n.id)
      |> Repo.all()

    latest = Map.new(singles ++ latest_of_kinds, &{card_key(&1), &1})

    # A card whose notifications went between the two queries is left out.
    Enum.flat_map(rows, fn row ->
      case latest[row.key] do
        nil ->
          []

        notification ->
          %{title: title, message: message} = Copy.rollup(notification.kind, row.devices, notification)

          [
            Map.merge(row, %{
              kind: notification.kind,
              level: notification.level,
              title: title,
              message: message,
              latest: notification
            })
          ]
      end
    end)
  end

  defp card_key(%Notification{kind: kind, id: id}) do
    if kind in Notification.device_kinds(), do: Atom.to_string(kind), else: id
  end

  @doc """
  The notifications on a rolled-up card, one for each device, the most
  recent first, at most `limit` of them.
  """
  @spec card_notifications(Product.t(), Notification.kind(), pos_integer()) :: [Notification.t()]
  def card_notifications(%Product{} = product, kind, limit) do
    Notification
    |> where([n], n.product_id == ^product.id and n.kind == ^kind)
    |> order_by([n], desc: n.last_occurred_at, desc: n.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  How many cards the product's notifications list has, in all and at each
  level. A kind rolled up across devices counts once.
  """
  @spec level_counts(Product.t()) :: %{
          all: non_neg_integer(),
          error: non_neg_integer(),
          warning: non_neg_integer(),
          info: non_neg_integer()
        }
  def level_counts(%Product{} = product) do
    counts =
      from(k in subquery(keyed(product, nil)),
        group_by: k.level,
        select: {k.level, count(k.key, :distinct)}
      )
      |> Repo.all()
      |> Map.new()

    by_level = Map.new(@levels, &{&1, Map.get(counts, &1, 0)})
    Map.put(by_level, :all, by_level |> Map.values() |> Enum.sum())
  end

  @doc """
  What each of `notifications` is about, and whether it is still there. See
  `NervesHub.ProductNotifications.Subjects`.
  """
  @spec subjects(Scope.t(), [Notification.t()]) :: %{Ecto.UUID.t() => Subjects.t()}
  defdelegate subjects(scope, notifications), to: Subjects, as: :for_notifications

  @doc """
  Dismisses one of the product's notifications. Anyone else looking at the
  product's notifications sees it go, with nothing to announce it.

  If what it was about happens again it comes back as a new notification.
  """
  @spec dismiss(Scope.t(), String.t()) :: {:ok, Notification.t()} | {:error, :not_found}
  def dismiss(%Scope{product: product}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {1, [notification]} <-
           Notification
           |> where([n], n.product_id == ^product.id and n.id == ^id)
           |> select([n], n)
           |> Repo.delete_all() do
      :ok = broadcast(product.id, "resolved")
      {:ok, notification}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Dismisses a rolled-up card: every one of the product's notifications of a
  kind raised per device. Returns how many went.
  """
  @spec dismiss_card(Scope.t(), String.t()) :: {:ok, pos_integer()} | {:error, :not_found}
  def dismiss_card(%Scope{product: product}, kind) when is_binary(kind) do
    with %{} = kinds <- Map.new(Notification.device_kinds(), &{Atom.to_string(&1), &1}),
         {:ok, kind} <- Map.fetch(kinds, kind),
         {count, _} when count > 0 <-
           Notification
           |> where([n], n.product_id == ^product.id and n.kind == ^kind)
           |> Repo.delete_all() do
      :ok = broadcast(product.id, "resolved")
      {:ok, count}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Dismisses all of the product's notifications, at every level, and tells
  anyone else looking at them who did it and how many cards went.
  """
  @spec delete_all(Scope.t()) :: :ok
  def delete_all(%Scope{product: product, user: user}) do
    %{all: count} = level_counts(product)

    {_deleted, _} =
      Notification
      |> where([n], n.product_id == ^product.id)
      |> Repo.delete_all()

    _ =
      Group.dispatch(NervesHub.Group, key(product.id), %Broadcast{
        topic: topic(product.id),
        event: "dismissed",
        payload: %{dismissed_by: %{id: user.id, name: user.name}, count: count}
      })

    :ok
  end

  @spec create_device_async_bulk_create_notification!(
          product_id :: pos_integer(),
          successfully_created_count :: non_neg_integer(),
          unsuccessfully_created_count :: non_neg_integer(),
          format :: String.t()
        ) :: Notification.t()
  def create_device_async_bulk_create_notification!(product_id, created, failed, format) do
    level =
      case {created, failed} do
        {0, 0} -> :warning
        {_created, 0} -> :info
        {0, _failed} -> :error
        _some_failed -> :warning
      end

    product_id
    |> Products.get_product!()
    |> raise!(
      :device_bulk_create,
      level,
      %{format: format, created: created, failed: failed},
      "device_bulk_create-#{DateTime.utc_now() |> DateTime.to_unix()}"
    )
  end

  @spec create_duplicate_device_identifier_notification!(
          product_id :: pos_integer(),
          identifier :: String.t(),
          auth_type :: atom()
        ) :: Notification.t()
  def create_duplicate_device_identifier_notification!(product_id, identifier, auth_type) do
    product_id
    |> Products.get_product!()
    |> raise!(
      :duplicate_device_identifier,
      :warning,
      %{identifier: identifier, auth_type: auth_type},
      "duplicate_device_identifier-#{identifier}"
    )
  end

  @spec create_wrong_websocket_host_notification!(device_info :: DeviceInfo.t(), host :: String.t()) ::
          Notification.t()
  def create_wrong_websocket_host_notification!(device_info, host) do
    raise!(
      %Product{id: device_info.product_id},
      :wrong_websocket_host,
      :warning,
      %{identifier: device_info.device_identifier, host: host},
      "wrong_websocket_host-#{device_info.device_identifier}"
    )
  end

  @spec create_soft_deleted_device_removed!(device :: Device.t()) :: Notification.t()
  def create_soft_deleted_device_removed!(device) do
    raise!(
      %Product{id: device.product_id},
      :soft_deleted_device,
      :info,
      %{identifier: device.identifier},
      "soft_deleted_device-#{device.identifier}"
    )
  end

  @spec create_missing_firmware_metadata_notification!(device :: Device.t()) :: Notification.t()
  def create_missing_firmware_metadata_notification!(device) do
    raise!(
      %Product{id: device.product_id},
      :missing_firmware_metadata,
      :warning,
      %{identifier: device.identifier},
      "missing_firmware_metadata-#{device.identifier}"
    )
  end

  @doc """
  A device could not be moved off an update mode its firmware cannot support.

  The device is stranded until someone acts: its deployment group will not push
  to it, and its firmware has no way to ask. Raised to the operator because
  nothing else will notice — the device goes on connecting perfectly happily.
  """
  def create_update_mode_revert_failed_notification!(device) do
    raise!(
      %Product{id: device.product_id},
      :update_mode_revert_failed,
      :error,
      %{identifier: device.identifier},
      "update_mode_revert_failed-#{device.identifier}"
    )
  end

  @doc """
  A device reported metric names too long to store.

  The readings were discarded; the rest of the report was kept. Raised to the
  operator because nothing else would notice -- the device goes on reporting
  perfectly happily, and the missing readings look like a metric the firmware
  simply does not collect.

  Deduplicated on the *device*, not on the offending name. A client generating
  unbounded names would otherwise get a notification row per name, which is the
  unbounded growth the cap exists to prevent.
  """
  @spec create_oversized_metric_keys_notification!(DeviceInfo.t(), String.t(), pos_integer(), pos_integer()) ::
          Notification.t()
  def create_oversized_metric_keys_notification!(device_info, example_key, count, max_bytes) do
    raise!(
      %Product{id: device_info.product_id},
      :oversized_metric_keys,
      :warning,
      %{
        identifier: device_info.device_identifier,
        example_key: String.slice(example_key, 0, 256),
        count: count,
        max_bytes: max_bytes
      },
      "oversized_metric_keys-#{device_info.device_identifier}"
    )
  end

  @doc """
  A workflow stopped part-way through a rollout and is waiting on a person.

  Raised to the operator because nothing else will notice. A halted workflow is
  quiet: devices carry on connecting, the deployment group still says it is
  active, and the only sign is a diagram nobody is looking at.

  Pass `broadcast: false` when raising it inside a transaction, and call
  `broadcast/2` once that commits. Told sooner, the notifications page reads
  the list back without it.
  """
  def create_workflow_halted_notification!(deployment_group, step, reason, opts \\ []) do
    {reason, level, failed} =
      case reason do
        {:failed, failed_count} -> {"failed", :error, %{failed_count: failed_count}}
        :awaiting_approval -> {"awaiting_approval", :info, %{}}
      end

    raise!(
      %Product{id: deployment_group.product_id},
      :workflow_halted,
      level,
      Map.merge(failed, %{
        deployment_group: deployment_group.name,
        deployment_group_id: deployment_group.id,
        step_number: step.number,
        step: DeploymentWorkflowStep.label(step),
        reason: reason
      }),
      # Keyed to the step rather than the deployment group, so a workflow that
      # stops twice at different stages says so twice.
      workflow_halted_key(deployment_group.id, step.id),
      opts
    )
  end

  @doc """
  A device could not start an extension it was asked to attach.

  Both ways that can happen end up here. `NervesHub.Extensions.Dispatch` reports
  the device failing to start the extension at all, which detaches it; an
  extension reports a failure of its own, which does not -- the local shell
  answering `request_shell` with a reason it has no pty is the case this was
  written for.

  Either way the extension is enabled and not working, and nothing about the
  device says so: it stays connected, and the toggle on its settings page stays
  on. The fix is almost always in the device's firmware, so it needs a person.

  Deduplicated on the device, the extension and the reason. Including the reason
  looks redundant next to `occurrence_count`, and is not: the conflict clause in
  `insert_and_notify!/1` updates the count and the timestamp but not the
  message, so a device that starts failing for a new reason would otherwise
  keep showing the old one.
  """
  @spec create_extension_failure_notification!(DeviceInfo.t(), String.t(), String.t() | nil) ::
          Notification.t()
  def create_extension_failure_notification!(%DeviceInfo{} = device_info, extension, reason) do
    reason = truncate_reason(reason)

    raise!(
      %Product{id: device_info.product_id},
      :extension_failure,
      :warning,
      %{identifier: device_info.device_identifier, extension: extension, reason: reason},
      # The changeset rejects spaces, and a reason is a sentence, so the reason
      # is keyed by hash rather than by its text.
      "extension_failure-#{extension}-#{device_info.device_identifier}-#{:erlang.phash2(reason)}"
    )
  end

  @doc """
  A device could not run the connecting code it was sent when it connected.

  Raised because nothing else shows it. The device stays connected and nothing
  on its page changes, so before this the only trace was a log line.

  Connecting code is usually set on a deployment group, so code that is wrong
  fails on every device in the group, every time one connects. That is why this
  is deduplicated on `connecting_code`, the code as the device was sent it,
  rather than on the device. A whole group failing on the same code makes one
  notification, named for the first device to fail, with every later failure in
  its count. Code that is changed and fails again makes a new notification
  carrying the new reason. The conflict clause in `insert_and_notify!/1` would
  keep the old one.
  """
  @spec create_connecting_code_failure_notification!(DeviceInfo.t(), String.t(), String.t() | nil) ::
          Notification.t()
  def create_connecting_code_failure_notification!(%DeviceInfo{} = device_info, connecting_code, reason) do
    reason = truncate_reason(reason)

    raise!(
      %Product{id: device_info.product_id},
      :connecting_code_failure,
      :warning,
      %{identifier: device_info.device_identifier, reason: reason},
      "connecting_code_failure-#{:erlang.phash2(connecting_code)}"
    )
  end

  @doc """
  A device reported more metrics in one report than will be stored.

  The report is kept, trimmed to the first `max_keys` names in sorted order --
  so the same readings are dropped every time rather than an arbitrary subset
  that changes shape between reports.

  Deduplicated on the device, for the same reason as
  `create_oversized_metric_keys_notification!/4`.
  """
  @spec create_too_many_metrics_notification!(DeviceInfo.t(), pos_integer(), pos_integer()) :: Notification.t()
  def create_too_many_metrics_notification!(device_info, reported, max_keys) do
    raise!(
      %Product{id: device_info.product_id},
      :too_many_metrics,
      :warning,
      %{identifier: device_info.device_identifier, reported: reported, max_keys: max_keys},
      "too_many_metrics-#{device_info.device_identifier}"
    )
  end

  @doc """
  A webhook was turned off because of how its endpoint answered. One
  notification for each product in `product_ids`, the products whose events
  the webhook was sending.

  Raised to the operator because nothing else will notice: the receiving
  system simply stops hearing about devices. Webhooks belong to the
  organization, which has no notifications of its own, so the products whose
  events stopped carry it. Names the endpoint by its host, since some
  receivers carry credentials in the URL itself.
  """
  @spec create_webhook_disabled_notifications!(Webhook.t(), [pos_integer()], String.t()) :: [Notification.t()]
  def create_webhook_disabled_notifications!(%Webhook{} = webhook, product_ids, reason) do
    host = URI.parse(webhook.url).host

    for product_id <- product_ids do
      raise!(
        %Product{id: product_id},
        :webhook_disabled,
        :error,
        %{webhook_id: webhook.id, host: host, reason: reason},
        "webhook_disabled-#{webhook.id}"
      )
    end
  end

  @doc """
  A Slack channel subscription was turned off because the channel could not
  be posted to. One notification for each product in `product_ids`, the
  products whose events the channel was getting.
  """
  @spec create_slack_subscription_disabled_notifications!(Subscription.t(), [pos_integer()], String.t()) ::
          [Notification.t()]
  def create_slack_subscription_disabled_notifications!(%Subscription{} = subscription, product_ids, reason) do
    for product_id <- product_ids do
      raise!(
        %Product{id: product_id},
        :slack_subscription_disabled,
        :error,
        %{slack_subscription_id: subscription.id, channel: subscription.channel_name, reason: reason},
        "slack_subscription_disabled-#{subscription.id}"
      )
    end
  end

  @doc """
  NervesHub stopped posting to a Teams or Discord channel because the chat
  service refused its webhook, one notification per product the channel
  heard.
  """
  def create_chat_webhook_disabled_notifications!(%ChatWebhook{} = channel, product_ids, reason) do
    service = ChatWebhooks.provider(channel.provider).label()

    for product_id <- product_ids do
      raise!(
        %Product{id: product_id},
        :chat_webhook_disabled,
        :error,
        %{chat_webhook_id: channel.id, channel: channel.name, service: service, reason: reason},
        "chat_webhook_disabled-#{channel.id}"
      )
    end
  end

  @doc """
  Take back the notice that a workflow had stopped.

  Raised when a workflow stops and cleared when it starts again, so the list
  reflects what needs attention now rather than everything that ever did. The
  same key the notice was raised under finds it, whether it was raised once or
  coalesced from several.

  Returns `{:ok, :resolved}` when there was a notice to take back, and
  `{:ok, :none}` when there was not. `broadcast: false` leaves telling the
  notifications page to `broadcast/2`, as for
  `create_workflow_halted_notification!/4`.
  """
  @spec resolve_workflow_halted_notification!(pos_integer(), pos_integer(), pos_integer(), keyword()) ::
          {:ok, :resolved | :none}
  def resolve_workflow_halted_notification!(product_id, deployment_group_id, step_id, opts \\ []) do
    resolve!(product_id, workflow_halted_key(deployment_group_id, step_id), opts)
  end

  defp resolve!(product_id, event_key, opts) do
    {deleted, _} =
      Notification
      |> where([n], n.product_id == ^product_id and n.event_key == ^event_key)
      |> Repo.delete_all()

    if deleted > 0 do
      if Keyword.get(opts, :broadcast, true), do: :ok = broadcast(product_id, "resolved")

      {:ok, :resolved}
    else
      {:ok, :none}
    end
  end

  @doc """
  Tells the product's notifications page that a notification was `"created"`
  or `"resolved"`, for a caller that changed one with `broadcast: false`.
  """
  @spec broadcast(pos_integer(), String.t()) :: :ok
  def broadcast(product_id, event) when event in ~w(created resolved) do
    _ =
      Group.dispatch(NervesHub.Group, key(product_id), %Broadcast{
        topic: topic(product_id),
        event: event,
        payload: %{}
      })

    :ok
  end

  defp workflow_halted_key(deployment_group_id, step_id) do
    "workflow_halted-#{deployment_group_id}-#{step_id}"
  end

  defp truncate_reason(nil), do: nil

  defp truncate_reason(reason) when is_binary(reason) do
    if String.length(reason) > @reason_max_length do
      String.slice(reason, 0, @reason_max_length - 1) <> "…"
    else
      reason
    end
  end

  defp truncate_reason(reason), do: truncate_reason(inspect(reason))

  # Raises a notification of `kind`, storing the copy that names what it's
  # about as its title and message, for where it's sent.
  defp raise!(product, kind, level, metadata, event_key, opts \\ []) do
    %{title: title, message: message} = Copy.full(kind, metadata)

    product
    |> Notification.new_changeset(%{
      kind: kind,
      title: title,
      message: message,
      level: level,
      metadata: metadata,
      event_key: event_key
    })
    |> insert_and_notify!(opts)
  end

  defp insert_and_notify!(changeset, opts) do
    conflict_query =
      Notification
      |> update([n],
        set: [
          last_occurred_at: fragment("EXCLUDED.last_occurred_at"),
          occurrence_count: fragment("?.occurrence_count + 1", n)
        ]
      )

    notification =
      Repo.insert!(changeset,
        on_conflict: conflict_query,
        conflict_target: [:product_id, :event_key],
        # Only the count, which tells a new notification from a recurrence.
        # Reading back the rest would hand callers string-keyed metadata.
        returning: [:occurrence_count]
      )

    # Only a new notification is news. The same one occurring again only
    # bumps its count, and would otherwise post the same thing to Slack each
    # time.
    if notification.occurrence_count == 1 do
      :ok =
        Integrations.dispatch(notification.product_id, "product.notification_created", fn ->
          %{
            notification: %{
              id: notification.id,
              title: notification.title,
              message: notification.message,
              level: to_string(notification.level)
            }
          }
        end)
    end

    if Keyword.get(opts, :broadcast, true), do: :ok = broadcast(notification.product_id, "created")

    notification
  end

  # Group key. "/" is Group's hierarchy separator, matching the other pub/sub
  # wrappers.
  defp key(product_id), do: "product_notifications/#{product_id}"

  # Preserved as the previous `Phoenix.PubSub` topic string.
  defp topic(product_id), do: "product_notifications:#{product_id}"

  @doc """
  How many cards the product's notifications list has. See `level_counts/1`.
  """
  @spec count(Product.t()) :: non_neg_integer()
  def count(product), do: level_counts(product).all
end
