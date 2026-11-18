defmodule NervesHub.ProductNotifications.Subjects do
  @moduledoc """
  What each notification on a page is about, and whether it is still there.

  A notification's kind says what it is about, and its metadata names it: a
  device's identifier, a deployment group, or the webhook, Slack subscription
  or chat channel that was turned off. Those are looked up together for a page of notifications, a
  query per kind, so the page can link to each one or say it has gone.

  The names come from the notification, not the lookup, so a subject keeps the
  name it had when the notification was raised after it has gone.
  """

  import Ecto.Query

  alias NervesHub.Accounts.Scope
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.Visibility
  alias NervesHub.Integrations.ChatWebhooks.ChatWebhook
  alias NervesHub.Integrations.Slack.Connection
  alias NervesHub.Integrations.Slack.Subscription
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Products.Notification
  alias NervesHub.Repo
  alias NervesHub.Webhooks.Webhook

  @typedoc """
  A notification's subject.

  `state` is `:live` when it can be linked to. A device is `:deleted` once
  deleted, from this product or for good, and `:moved` when it is now in
  another of the organization's products. Anything else that has gone is
  `:removed`.

  `ref` is what a live subject's page is found by: a device's identifier, a
  deployment group's name as it is now. Integrations are all on the
  organization's Integrations page, and have none.
  """
  @type t :: %{
          kind: :device | :deployment_group | :webhook | :slack | :chat,
          label: String.t(),
          state: :live | :deleted | :moved | :removed,
          ref: String.t() | nil
        }

  @doc """
  The subjects of `notifications`, keyed by notification ID. A notification
  about nothing in particular, such as a finished device import, has none.
  """
  @spec for_notifications(Scope.t(), [Notification.t()]) :: %{Ecto.UUID.t() => t()}
  def for_notifications(%Scope{} = scope, notifications) do
    refs = Enum.flat_map(notifications, &ref/1)
    found = lookup(scope, refs)

    Map.new(refs, fn {id, kind, key, label} ->
      {state, ref} = subject_state(kind, Map.get(found, {kind, key}))
      {id, %{kind: kind, label: label, state: state, ref: ref}}
    end)
  end

  # What each kind of notification is about, and the metadata key that names
  # it. A kind left out, such as a finished device import, is about nothing
  # in particular.
  @subject_keys Map.merge(
                  Map.new([:connecting_code_failure | Notification.device_kinds()], &{&1, {:device, :identifier}}),
                  %{
                    workflow_halted: {:deployment_group, :deployment_group},
                    webhook_disabled: {:webhook, :webhook_id},
                    slack_subscription_disabled: {:slack, :slack_subscription_id},
                    chat_webhook_disabled: {:chat, :chat_webhook_id}
                  }
                )

  # {notification id, kind, the key it is looked up by, the name to show}
  defp ref(%Notification{id: id, kind: kind, metadata: metadata} = notification) do
    with {subject, key} <- Map.get(@subject_keys, kind),
         value when not is_nil(value) <- meta(metadata, key) do
      [{id, subject, lookup_key(subject, value, notification), label(subject, value, metadata)}]
    else
      _ -> []
    end
  end

  # Notifications raised before the deployment group's ID was stored carry it
  # in their key.
  defp lookup_key(:deployment_group, name, %Notification{metadata: metadata, event_key: event_key}) do
    meta(metadata, :deployment_group_id) || deployment_group_id_from_key(event_key) || name
  end

  defp lookup_key(_subject, value, _notification), do: value

  defp label(:webhook, _id, metadata), do: meta(metadata, :host) || "webhook"
  defp label(:slack, _id, metadata), do: "##{meta(metadata, :channel)}"
  defp label(:chat, _id, metadata), do: meta(metadata, :channel) || "channel"
  defp label(_subject, value, _metadata), do: value

  # Metadata reads back from the database with string keys, and comes back
  # from an insert with the atom keys it was written with.
  defp meta(metadata, key) when is_map(metadata) do
    Map.get(metadata, Atom.to_string(key)) || Map.get(metadata, key)
  end

  defp meta(_metadata, _key), do: nil

  defp deployment_group_id_from_key("workflow_halted-" <> rest) do
    rest
    |> String.split("-")
    |> hd()
    |> Integer.parse()
    |> case do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp deployment_group_id_from_key(_event_key), do: nil

  defp lookup(scope, refs) do
    keys =
      Enum.group_by(refs, fn {_id, kind, _key, _label} -> kind end, fn {_id, _kind, key, _label} -> key end)

    Map.new(
      devices(scope, keys[:device]) ++
        deployment_groups(scope, keys[:deployment_group]) ++
        webhooks(scope, keys[:webhook]) ++
        slack_subscriptions(scope, keys[:slack]) ++
        chat_webhooks(scope, keys[:chat])
    )
  end

  defp devices(_scope, nil), do: []

  # A device with the identifier in another of the organization's products is
  # the same device, moved. Only the fact is shown, not where to.
  defp devices(%Scope{product: product, user: user}, identifiers) do
    Device
    |> where([d], d.org_id == ^product.org_id and d.identifier in ^Enum.uniq(identifiers))
    |> Visibility.where_visible(user)
    |> select([d], {d.identifier, {d.product_id, d.deleted_at}})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {identifier, rows} ->
      found =
        cond do
          Enum.any?(rows, &match?({id, nil} when id == product.id, &1)) -> :live
          Enum.any?(rows, &match?({id, _deleted_at} when id == product.id, &1)) -> :deleted
          Enum.any?(rows, &match?({_id, nil}, &1)) -> :moved
          true -> :deleted
        end

      {{:device, identifier}, {found, identifier}}
    end)
  end

  defp deployment_groups(_scope, nil), do: []

  defp deployment_groups(%Scope{product: product}, keys) do
    {ids, names} = Enum.split_with(keys, &is_integer/1)

    DeploymentGroup
    |> where([dg], dg.product_id == ^product.id and (dg.id in ^ids or dg.name in ^names))
    |> select([dg], {dg.id, dg.name})
    |> Repo.all()
    |> Enum.flat_map(fn {id, name} ->
      [{{:deployment_group, id}, name}, {{:deployment_group, name}, name}]
    end)
  end

  defp webhooks(_scope, nil), do: []

  defp webhooks(%Scope{product: product}, ids) do
    Webhook
    |> where([w], w.org_id == ^product.org_id and w.id in ^ids)
    |> select([w], w.id)
    |> Repo.all()
    |> Enum.map(&{{:webhook, &1}, :live})
  end

  defp slack_subscriptions(_scope, nil), do: []

  defp slack_subscriptions(%Scope{product: product}, ids) do
    Subscription
    |> join(:inner, [s], c in Connection, on: c.id == s.connection_id)
    |> where([s, c], c.org_id == ^product.org_id and s.id in ^ids)
    |> select([s], s.id)
    |> Repo.all()
    |> Enum.map(&{{:slack, &1}, :live})
  end

  defp chat_webhooks(_scope, nil), do: []

  defp chat_webhooks(%Scope{product: product}, ids) do
    ChatWebhook
    |> where([c], c.org_id == ^product.org_id and c.id in ^ids)
    |> select([c], c.id)
    |> Repo.all()
    |> Enum.map(&{{:chat, &1}, :live})
  end

  # What `lookup/2` found for a subject: a device's state and identifier, a
  # deployment group's name now, or `:live` for an integration.
  defp subject_state(:device, nil), do: {:deleted, nil}
  defp subject_state(:device, {:live, identifier}), do: {:live, identifier}
  defp subject_state(:device, {state, _identifier}), do: {state, nil}
  defp subject_state(_kind, nil), do: {:removed, nil}
  defp subject_state(:deployment_group, name), do: {:live, name}
  defp subject_state(_kind, :live), do: {:live, nil}
end
