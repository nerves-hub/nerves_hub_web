defmodule NervesHub.Integrations do
  @moduledoc """
  Where device events leave NervesHub: to an organization's webhooks
  (`NervesHub.Webhooks`), Slack channels
  (`NervesHub.Integrations.Slack.Subscriptions`), and Microsoft Teams and
  Discord channels (`NervesHub.Integrations.ChatWebhooks`).

  ## Raising events

  Code where something happens to a device calls `dispatch/3` with the
  product, the event type and a function that builds the event's `data`.
  When nothing that hears the product wants the type, which is nearly every
  call, that is one ETS read (`NervesHub.Integrations.Cache`) and nothing
  else: the function is not run, and nothing touches the database. Otherwise
  the data is built and cleaned once and handed to each listener's kind of
  integration to send.

  Events are raised on whichever node the device is connected to. Device
  nodes run no Oban queues but can insert jobs, so what goes out goes out
  from web nodes, off the device's connection.

  Called inside a transaction, what is queued is part of it: an outcome that
  rolls back takes its events with it.

  ## Who hears a product

  Integrations belong to the organization, and each one hears every product
  in it or the products it lists. A change to any of them must call
  `invalidate/1` with the organization's id after it commits, so that
  dispatching sees the change at once on every node.
  """

  import Ecto.Query

  alias NervesHub.Accounts.Org
  alias NervesHub.Integrations.Cache
  alias NervesHub.Integrations.ChannelEvents
  alias NervesHub.Integrations.ChatWebhooks
  alias NervesHub.Integrations.ChatWebhooks.ChatWebhook
  alias NervesHub.Integrations.Slack.Subscription
  alias NervesHub.Integrations.Slack.Subscriptions
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias NervesHub.Webhooks
  alias NervesHub.Webhooks.Webhook

  @doc """
  Hands `type` to every enabled integration that hears the product and wants
  the type.

  `build_data` returns the event's `data`, without the `org` and `product`
  this adds, and is only called when somebody wants the event. Strings in it
  are made safe to store and encode, since much of what an event carries is
  whatever a device chose to send.
  """
  @spec dispatch(pos_integer() | nil, String.t(), (-> map())) :: :ok
  def dispatch(product_id, type, build_data) when is_function(build_data, 0) do
    case listeners(product_id, type) do
      {_names, []} ->
        :ok

      {names, listeners} ->
        data = build_data.() |> Map.merge(names) |> scrub()

        for {kind, ids} <- Enum.group_by(listeners, &elem(&1, 0), &elem(&1, 1)) do
          :ok = deliver(kind, ids, type, data)
        end

        :ok
    end
  end

  defp deliver(:webhook, webhook_ids, type, data), do: Webhooks.queue_deliveries(webhook_ids, type, data)
  defp deliver(:slack, subscription_ids, type, data), do: Subscriptions.queue_events(subscription_ids, type, data)
  defp deliver(:chat_webhook, channel_ids, type, data), do: ChatWebhooks.queue_events(channel_ids, type, data)

  @doc """
  Whether any enabled integration that hears the product wants `type`.

  For callers that would have to do work just to find out which devices an
  event is about, such as the stale connection sweep. Everyone else can call
  `dispatch/3`, which checks the same thing.
  """
  @spec subscribed?(pos_integer() | nil, String.t()) :: boolean()
  def subscribed?(product_id, type) do
    match?({_names, [_ | _]}, listeners(product_id, type))
  end

  @doc """
  Forget who hears the organization's products, here and on every other
  node. Called after any change to the organization's integrations commits.
  """
  @spec invalidate(pos_integer()) :: :ok
  def invalidate(org_id), do: Cache.invalidate(org_id)

  # A connection's `product_id` is nullable (it is cleared when the product
  # goes), and a connection without one has no product's integrations to tell.
  defp listeners(nil, _type), do: {%{}, []}

  defp listeners(product_id, type) do
    case Cache.fetch(product_id, fn -> load_listeners(product_id) end) do
      nil ->
        {%{}, []}

      %{names: names, listeners: listeners} ->
        {names, for({kind, id, events} <- listeners, type in events, do: {kind, id})}
    end
  end

  # What dispatching needs to know about a product, in one query: the
  # product's organization (the cache drops entries by it), the enabled
  # integrations that hear the product and the events each wants, and the
  # names every event carries. The value is `nil` when nothing hears the
  # product, which is what the cache holds for nearly every product.
  #
  # The integrations are left-joined so that a product nothing hears still
  # comes back, with its organization, as a single row without one.
  defp load_listeners(product_id) do
    from(p in Product,
      join: o in Org,
      on: o.id == p.org_id,
      left_join: l in subquery(hearing(product_id)),
      on: l.org_id == o.id,
      where: p.id == ^product_id and is_nil(p.deleted_at) and is_nil(o.deleted_at),
      select: {o.id, o.name, p.name, l.kind, l.id, l.events}
    )
    |> Repo.all()
    |> to_listeners()
  end

  # The enabled integrations of any organization that hear the product: the
  # join above keeps the product's own. An integration lists a product at most
  # once (a unique index), so this is one row per integration.
  defp hearing(product_id) do
    from(w in Webhook,
      left_join: wp in "webhook_products",
      on: wp.webhook_id == w.id and wp.product_id == ^product_id,
      where: w.enabled and (w.all_products or not is_nil(wp.webhook_id)),
      select: %{kind: "webhook", id: w.id, org_id: w.org_id, events: w.events},
      union_all: ^slack_hearing(product_id),
      union_all: ^chat_webhooks_hearing(product_id)
    )
  end

  defp slack_hearing(product_id) do
    from(s in Subscription,
      join: c in assoc(s, :connection),
      left_join: sp in "slack_subscription_products",
      on: sp.subscription_id == s.id and sp.product_id == ^product_id,
      where: s.enabled and (s.all_products or not is_nil(sp.subscription_id)),
      select: %{kind: "slack", id: s.id, org_id: c.org_id, events: s.events}
    )
  end

  defp chat_webhooks_hearing(product_id) do
    from(w in ChatWebhook,
      left_join: wp in "chat_webhook_products",
      on: wp.chat_webhook_id == w.id and wp.product_id == ^product_id,
      where: w.enabled and (w.all_products or not is_nil(wp.chat_webhook_id)),
      select: %{kind: "chat_webhook", id: w.id, org_id: w.org_id, events: w.events}
    )
  end

  defp to_listeners([]), do: {nil, nil}
  defp to_listeners([{org_id, _org_name, _product_name, nil, nil, nil}]), do: {org_id, nil}

  defp to_listeners([{org_id, org_name, product_name, _kind, _id, _events} | _] = rows) do
    {org_id,
     %{
       names: %{org: %{name: org_name}, product: %{name: product_name}},
       listeners: for({_, _, _, kind, id, events} <- rows, do: listener(kind, id, events))
     }}
  end

  # A Slack, Teams or Discord channel names its events by
  # `NervesHub.Integrations.ChannelEvents` key, which is not always the type
  # raised: both "update failed" and "update succeeded" come from
  # `device.firmware_update.finished`.
  defp listener("webhook", id, events), do: {:webhook, id, events}
  defp listener("slack", id, events), do: {:slack, id, ChannelEvents.sources(events)}
  defp listener("chat_webhook", id, events), do: {:chat_webhook, id, ChannelEvents.sources(events)}

  # Event data includes text devices sent: failure reasons, alarm descriptions,
  # metadata. Invalid UTF-8 would fail to encode, and a NUL is valid JSON that
  # PostgreSQL refuses to store in a job's arguments or a JSON column. Either
  # would take the event, and anything else in the transaction raising it,
  # down with it.
  defp scrub(%_{} = struct), do: struct
  defp scrub(map) when is_map(map), do: Map.new(map, fn {key, value} -> {scrub(key), scrub(value)} end)
  defp scrub(list) when is_list(list), do: Enum.map(list, &scrub/1)

  defp scrub(binary) when is_binary(binary) do
    binary
    |> String.replace_invalid()
    |> String.replace(<<0>>, "")
  end

  defp scrub(other), do: other
end
