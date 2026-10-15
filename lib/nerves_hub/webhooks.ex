defmodule NervesHub.Webhooks do
  @moduledoc """
  Webhooks: HTTP endpoints an organization sends device events to.

  An organization has up to twenty webhooks, each with a URL, a signing
  secret, the event types it subscribes to (`NervesHub.Webhooks.Events`), and
  the products whose events it sends: every product in the organization, or
  the ones it lists. They are configured on the organization's Integrations
  settings page. `docs/webhooks.md` is the receiver's documentation: payloads,
  headers, signing and retries.

  ## Raising events

  Code where something happens to a device calls `dispatch/3` with the product,
  the event type and a function that builds the event's `data`. When none of
  the enabled webhooks that hear the product subscribe to the type, which is
  nearly every call, that is one ETS read (`NervesHub.Webhooks.Cache`) and
  nothing else: the function is not run, and nothing touches the database.
  Otherwise the event is encoded once and one
  `NervesHub.Workers.DeliverWebhook` job is inserted per subscribed webhook.

  Events are raised on whichever node the device is connected to. Device nodes
  run no Oban queues but can insert jobs, so deliveries go out from web nodes,
  off the device's connection.

  Called inside a transaction, the jobs are part of it: an outcome that rolls
  back takes its webhook with it.

  ## Delivery

  At least once, unordered. Each event has an id, sent as `webhook-id`, that
  stays the same across retries so a receiver can discard a repeat. See
  `NervesHub.Workers.DeliverWebhook` for retries, and `record_failure/3` for
  how a failing endpoint is backed off and eventually turned off.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.Scope
  alias NervesHub.AuditLogs.OrgTemplates
  alias NervesHub.ProductNotifications
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias NervesHub.Webhooks.Cache
  alias NervesHub.Webhooks.Delivery
  alias NervesHub.Webhooks.Events
  alias NervesHub.Webhooks.Webhook
  alias NervesHub.Workers.DeliverWebhook

  require Logger

  @max_webhooks_per_org 20

  # An encoded event larger than this is dropped rather than queued. The
  # biggest legitimate payload, a full metrics batch, is a few tens of
  # kilobytes; anything near this is a device sending something it should not,
  # and every delivery attempt would carry it again.
  @max_body_bytes 256 * 1024

  # Failures are written to the webhook at most this often. A dead endpoint
  # fails every delivery queued for it, and each one writing the same row
  # would turn one broken receiver into contention on that row.
  @failure_write_interval_seconds 30

  # While an endpoint is failing, deliveries in this window after a failure
  # skip the request and count as failed attempts themselves. See
  # `cooling_down?/2`.
  @cooldown_seconds 30

  # An endpoint that has not accepted a single delivery for this long is
  # turned off, and the members of the products it served are told.
  @disable_after_hours 24

  @doc "How many webhooks an organization may have."
  def max_webhooks_per_org(), do: @max_webhooks_per_org

  @doc "The organization's webhooks, oldest first, with the products each lists."
  @spec list_webhooks(Org.t()) :: [Webhook.t()]
  def list_webhooks(%Org{id: org_id}) do
    Webhook
    |> where(org_id: ^org_id)
    |> order_by(asc: :inserted_at, asc: :id)
    |> preload(:products)
    |> Repo.all()
  end

  @doc """
  One of the organization's webhooks, with the products it lists. Raises if
  the organization has no webhook with that id.
  """
  @spec get_webhook!(Org.t(), pos_integer() | String.t()) :: Webhook.t()
  def get_webhook!(%Org{id: org_id}, id) do
    Webhook
    |> where(id: ^id, org_id: ^org_id)
    |> preload(:products)
    |> Repo.one!()
  end

  @doc """
  One of the organization's webhooks, with the products it lists, or
  `{:error, :not_found}`, including for an id that is not a number (it
  arrives from a URL).
  """
  @spec fetch_webhook(Org.t(), pos_integer() | String.t()) :: {:ok, Webhook.t()} | {:error, :not_found}
  def fetch_webhook(%Org{id: org_id}, id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} ->
        Webhook
        |> where(id: ^id, org_id: ^org_id)
        |> preload(:products)
        |> Repo.fetch()

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  A changeset for the webhook form. `attrs` names products by name, and they
  are looked up in `org`.
  """
  @spec change_webhook(Org.t(), Webhook.t(), map()) :: Changeset.t()
  def change_webhook(%Org{} = org, %Webhook{} = webhook, attrs \\ %{}) do
    attrs = scope_attrs(attrs)

    webhook
    |> Repo.preload(:products)
    |> Webhook.changeset(attrs, find_products(org, attrs))
  end

  @doc """
  Adds a webhook to the scope's organization, with a newly generated signing
  secret.

  `attrs` may limit it to some of the organization's products, by name, with
  `"all_products" => false` and `"products"`. Naming products without saying
  `"all_products"` limits it to them. Otherwise it sends every product's
  events, including products added later.

  Returns `{:error, :too_many_webhooks}` when the organization already has
  `max_webhooks_per_org/0`. The limit bounds how many deliveries a single
  device event can fan out into.
  """
  @spec create_webhook(Scope.t(), map()) :: {:ok, Webhook.t()} | {:error, Changeset.t() | :too_many_webhooks}
  def create_webhook(%Scope{org: org, user: user}, attrs) do
    attrs = scope_attrs(attrs)

    Repo.transact(fn ->
      count = Webhook |> where(org_id: ^org.id) |> Repo.aggregate(:count)

      with true <- count < @max_webhooks_per_org || {:error, :too_many_webhooks},
           {:ok, webhook} <- org |> Webhook.create_changeset(attrs, find_products(org, attrs)) |> Repo.insert() do
        :ok = OrgTemplates.audit_webhook_created(user, org, webhook)
        {:ok, webhook}
      end
    end)
    |> tap(&invalidate_on_success(&1, org))
  end

  @doc """
  Changes a webhook's URL, description, events, products, or whether it is on.
  Products are named and limited as `create_webhook/2` describes; a change
  that names none leaves them as they are.
  """
  @spec update_webhook(Scope.t(), Webhook.t(), map()) :: {:ok, Webhook.t()} | {:error, Changeset.t()}
  def update_webhook(%Scope{org: org, user: user}, %Webhook{} = webhook, attrs) do
    attrs = scope_attrs(attrs)

    Repo.transact(fn ->
      changeset =
        webhook
        |> Repo.preload(:products)
        |> Webhook.changeset(attrs, find_products(org, attrs))

      with {:ok, updated} <- Repo.update(changeset) do
        :ok = OrgTemplates.audit_webhook_updated(user, org, updated)
        {:ok, updated}
      end
    end)
    |> tap(&invalidate_on_success(&1, org))
  end

  @doc """
  Removes a webhook. Deliveries already queued for it are dropped when they
  come up.
  """
  @spec delete_webhook(Scope.t(), Webhook.t()) :: {:ok, Webhook.t()} | {:error, Changeset.t()}
  def delete_webhook(%Scope{org: org, user: user}, %Webhook{} = webhook) do
    Repo.transact(fn ->
      with {:ok, deleted} <- Repo.delete(webhook) do
        :ok = OrgTemplates.audit_webhook_deleted(user, org, deleted)
        {:ok, deleted}
      end
    end)
    |> tap(&invalidate_on_success(&1, org))
  end

  @doc """
  Replaces the webhook's signing secret. Deliveries signed from now on, retries
  included, use the new one.
  """
  @spec regenerate_secret(Scope.t(), Webhook.t()) :: {:ok, Webhook.t()} | {:error, Changeset.t()}
  def regenerate_secret(%Scope{org: org, user: user}, %Webhook{} = webhook) do
    Repo.transact(fn ->
      with {:ok, updated} <- webhook |> Webhook.regenerate_secret_changeset() |> Repo.update() do
        :ok = OrgTemplates.audit_webhook_secret_regenerated(user, org, updated)
        {:ok, updated}
      end
    end)
  end

  # Naming products is asking for those products, so a change that lists
  # them without saying `all_products` means `all_products: false`. Only
  # string-keyed attributes name products: they come from a form or the API.
  defp scope_attrs(%{"products" => _} = attrs) when not is_map_key(attrs, "all_products") do
    Map.put(attrs, "all_products", false)
  end

  defp scope_attrs(attrs), do: attrs

  # The products a change names, looked up among the organization's own, by
  # name because the API knows products by name. Looking them up here, not
  # anywhere a caller could pass a product in, is what keeps a webhook from
  # hearing another organization's devices.
  defp find_products(%Org{id: org_id}, %{"products" => names}) when is_list(names) do
    if Enum.all?(names, &is_binary/1) do
      names = Enum.uniq(names)

      products =
        Product
        |> where([p], p.org_id == ^org_id and p.name in ^names)
        |> Repo.exclude_deleted()
        |> order_by(:name)
        |> Repo.all()

      found = MapSet.new(products, & &1.name)
      {products, Enum.reject(names, &MapSet.member?(found, &1))}
    else
      :invalid
    end
  end

  defp find_products(_org, %{"products" => _not_a_list}), do: :invalid
  defp find_products(_org, _attrs), do: nil

  @doc """
  Sends a `webhook.test` event to the webhook straight away, and returns how
  it went.

  Runs in the caller's process and makes the request itself, rather than
  queueing a job: the person who pressed the button is waiting to see the
  answer. Sent whether or not the webhook is on, and recorded nowhere, so
  testing an endpoint never changes what the webhook says about its
  deliveries.
  """
  @spec send_test_event(Scope.t(), Webhook.t()) :: Delivery.result()
  def send_test_event(%Scope{org: org, user: user}, %Webhook{} = webhook) do
    data = %{
      org: %{name: org.name},
      message: "A test event sent by #{user.name} from NervesHub."
    }

    Delivery.deliver(webhook, new_event_id(), encode(Events.test_type(), data))
  end

  @doc """
  Queues `type` for delivery to every enabled webhook that hears the product
  and subscribes to the type.

  `build_data` returns the event's `data`, without the `org` and `product`
  this adds, and is only called when there is somebody to send it to. Strings
  in it are made safe to store and encode, since much of what an event carries
  is whatever a device chose to send.
  """
  @spec dispatch(pos_integer(), String.t(), (-> map())) :: :ok
  def dispatch(product_id, type, build_data) when is_function(build_data, 0) do
    case subscribers(product_id, type) do
      {_names, []} ->
        :ok

      {names, webhook_ids} ->
        body = encode(type, Map.merge(build_data.(), names))
        enqueue(product_id, type, webhook_ids, body)
    end
  end

  @doc """
  Whether any enabled webhook that hears the product subscribes to `type`.

  For callers that would have to do work just to find out which devices an
  event is about, such as the stale connection sweep. Everyone else can call
  `dispatch/3`, which checks the same thing.
  """
  @spec subscribed?(pos_integer(), String.t()) :: boolean()
  def subscribed?(product_id, type) do
    match?({_names, [_ | _]}, subscribers(product_id, type))
  end

  # A connection's `product_id` is nullable (it is cleared when the product
  # goes), and a connection without one has no product's webhooks to tell.
  defp subscribers(nil, _type), do: {%{}, []}

  defp subscribers(product_id, type) do
    case Cache.fetch(product_id, fn -> load_subscriptions(product_id) end) do
      nil ->
        {%{}, []}

      %{names: names, webhooks: webhooks} ->
        {names, for({id, events} <- webhooks, type in events, do: id)}
    end
  end

  # What dispatching needs to know about a product, in one query: the
  # product's organization (the cache drops entries by it), the enabled
  # webhooks that hear the product and their events, and the names every event
  # carries. The value is `nil` when no webhook hears the product, which is
  # what the cache holds for nearly every product.
  #
  # The webhooks are left-joined so that a product no webhook hears still
  # comes back, with its organization, as a single row without one.
  defp load_subscriptions(product_id) do
    from(p in Product,
      join: o in Org,
      on: o.id == p.org_id,
      left_join: w in subquery(hearing(product_id)),
      on: w.org_id == o.id,
      where: p.id == ^product_id and is_nil(p.deleted_at) and is_nil(o.deleted_at),
      select: {o.id, o.name, p.name, w.id, w.events}
    )
    |> Repo.all()
    |> subscriptions()
  end

  # The enabled webhooks that hear the product, of any organization: the join
  # above keeps the product's own. A webhook lists a product at most once (a
  # unique index), so this is one row per webhook.
  defp hearing(product_id) do
    from(w in Webhook,
      left_join: wp in "webhook_products",
      on: wp.webhook_id == w.id and wp.product_id == ^product_id,
      where: w.enabled and (w.all_products or not is_nil(wp.webhook_id)),
      select: %{id: w.id, org_id: w.org_id, events: w.events}
    )
  end

  defp subscriptions([]), do: {nil, nil}
  defp subscriptions([{org_id, _org_name, _product_name, nil, _events}]), do: {org_id, nil}

  defp subscriptions([{org_id, org_name, product_name, _id, _events} | _] = rows) do
    {org_id,
     %{
       names: %{org: %{name: org_name}, product: %{name: product_name}},
       webhooks: for({_, _, _, id, events} <- rows, do: {id, events})
     }}
  end

  defp enqueue(product_id, type, _webhook_ids, body) when byte_size(body) > @max_body_bytes do
    Logger.warning("Dropped a #{type} webhook event for product #{product_id}: #{byte_size(body)} bytes encoded")
    :ok
  end

  defp enqueue(_product_id, type, webhook_ids, body) do
    event_id = new_event_id()

    _jobs =
      webhook_ids
      |> Enum.map(&DeliverWebhook.new(%{webhook_id: &1, event_id: event_id, type: type, body: body}))
      |> Oban.insert_all()

    :ok
  end

  # The specification asks only that ids are unique and contain no full stop.
  # UUIDv7s sort by time, which makes them easier to read in a receiver's logs.
  defp new_event_id(), do: "msg_" <> UUIDv7.generate()

  defp encode(type, data) do
    Jason.encode!(%{
      type: type,
      timestamp: DateTime.utc_now(),
      data: scrub(data)
    })
  end

  # Event data includes text devices sent: failure reasons, alarm descriptions,
  # metadata. Invalid UTF-8 would fail to encode, and a NUL is valid JSON that
  # PostgreSQL refuses to store in the job's arguments. Either would take the
  # event, and anything else in the transaction raising it, down with it.
  defp scrub(%_{} = struct), do: struct
  defp scrub(map) when is_map(map), do: Map.new(map, fn {key, value} -> {scrub(key), scrub(value)} end)
  defp scrub(list) when is_list(list), do: Enum.map(list, &scrub/1)

  defp scrub(binary) when is_binary(binary) do
    binary
    |> String.replace_invalid()
    |> String.replace(<<0>>, "")
  end

  defp scrub(other), do: other

  @doc """
  The webhook, if deliveries to it should still go out: it exists, it is on,
  and its organization has not been deleted.
  """
  @spec deliverable_webhook(pos_integer()) :: Webhook.t() | nil
  def deliverable_webhook(id) do
    Webhook
    |> join(:inner, [w], o in Org, on: o.id == w.org_id)
    |> where([w, o], w.id == ^id and w.enabled and is_nil(o.deleted_at))
    |> Repo.one()
  end

  @doc """
  Whether deliveries to the webhook should skip the request for now, because
  its endpoint failed moments ago.

  An endpoint that times out holds a delivery worker for the whole timeout,
  and every webhook on the instance shares those workers. Without this, one
  product's unreachable endpoint, fed by a busy fleet, could fill the queue
  and hold up everybody else's deliveries. With it, a failing endpoint costs
  one real request every `#{@cooldown_seconds}` seconds, and the deliveries in
  between fail without waiting.
  """
  @spec cooling_down?(Webhook.t(), DateTime.t()) :: boolean()
  def cooling_down?(%Webhook{failing_since: nil}, _now), do: false
  def cooling_down?(%Webhook{last_error_at: nil}, _now), do: false

  def cooling_down?(%Webhook{last_error_at: last_error_at}, now) do
    DateTime.diff(now, last_error_at) < @cooldown_seconds
  end

  @doc """
  The endpoint accepted a delivery, so it is no longer failing.

  Writes only when it was: a healthy webhook's successes cost nothing.
  """
  @spec record_success(Webhook.t()) :: :ok
  def record_success(%Webhook{failing_since: nil}), do: :ok

  def record_success(%Webhook{id: id}) do
    _ =
      Webhook
      |> where([w], w.id == ^id and not is_nil(w.failing_since))
      |> Repo.update_all(set: [failing_since: nil])

    :ok
  end

  @doc """
  The endpoint refused a delivery, or could not be reached.

  Records when the endpoint started failing and the latest error, throttled to
  one write every `#{@failure_write_interval_seconds}` seconds per webhook.

  Turns the webhook off when the endpoint answered `410 Gone`, which the
  Standard Webhooks specification reserves for a receiver saying it wants no
  more deliveries, or when it has been failing for `#{@disable_after_hours}`
  hours. Either way, each product it was sending events for gets a
  notification saying so.

  Returns `:disabled` when the webhook was turned off.
  """
  @spec record_failure(Webhook.t(), pos_integer() | nil, String.t()) :: :ok | :disabled
  def record_failure(%Webhook{} = webhook, 410, _message) do
    disable(webhook, "the endpoint answered 410 Gone, asking for no more deliveries")
  end

  def record_failure(%Webhook{id: id} = webhook, _status, message) do
    now = DateTime.utc_now(:second)
    throttle = DateTime.add(now, -@failure_write_interval_seconds)

    Webhook
    |> where([w], w.id == ^id)
    |> where([w], is_nil(w.failing_since) or is_nil(w.last_error_at) or w.last_error_at < ^throttle)
    |> select([w], w.failing_since)
    |> update([w],
      set: [
        failing_since: fragment("COALESCE(?, ?)", w.failing_since, type(^now, :utc_datetime)),
        last_error: ^String.slice(message, 0, 500),
        last_error_at: ^now
      ]
    )
    |> Repo.update_all([])
    |> case do
      {1, [failing_since]} ->
        if DateTime.diff(now, failing_since, :hour) >= @disable_after_hours do
          disable(webhook, "its endpoint has not accepted a delivery for #{@disable_after_hours} hours")
        else
          :ok
        end

      {0, _} ->
        :ok
    end
  end

  defp disable(%Webhook{id: id, org_id: org_id} = webhook, reason) do
    {count, _} =
      Webhook
      |> where([w], w.id == ^id and w.enabled)
      |> Repo.update_all(set: [enabled: false, disabled_reason: "Turned off because #{reason}."])

    # Only the delivery that actually turned it off says so. Others failing at
    # the same moment find it already off.
    _ =
      if count == 1 do
        :ok = Cache.invalidate(org_id)
        ProductNotifications.create_webhook_disabled_notifications!(webhook, heard_product_ids(webhook), reason)
      end

    :disabled
  end

  # The products whose events the webhook was sending, which are the ones
  # whose members need to hear that it stopped.
  defp heard_product_ids(%Webhook{all_products: true, org_id: org_id}) do
    Product
    |> where(org_id: ^org_id)
    |> Repo.exclude_deleted()
    |> select([p], p.id)
    |> Repo.all()
  end

  defp heard_product_ids(%Webhook{id: id}) do
    from(wp in "webhook_products",
      join: p in Product,
      on: p.id == wp.product_id,
      where: wp.webhook_id == ^id and is_nil(p.deleted_at),
      select: p.id
    )
    |> Repo.all()
  end

  defp invalidate_on_success({:ok, _webhook}, %Org{id: org_id}), do: Cache.invalidate(org_id)
  defp invalidate_on_success(_error, _org), do: :ok
end
