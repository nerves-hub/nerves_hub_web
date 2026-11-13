defmodule NervesHub.Integrations.Slack.Subscription do
  @moduledoc """
  A Slack channel an organization's device events are posted to, through one
  of its workspace connections.

  Like a webhook, it hears every product in the organization
  (`all_products`) or the products it lists, and is sent the events it names
  (`NervesHub.Integrations.ChannelEvents`). `last_error` and `last_error_at` describe the
  channel as posting last found it; `disabled_reason` is set when posting
  turned the subscription off, and cleared when a person turns it back on.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Integrations.ChannelEvents
  alias NervesHub.Integrations.ProductScope
  alias NervesHub.Integrations.Slack.Connection
  alias NervesHub.Products.Product

  @type t :: %__MODULE__{}

  schema "slack_subscriptions" do
    belongs_to(:connection, Connection)

    many_to_many(:products, Product,
      join_through: "slack_subscription_products",
      join_keys: [subscription_id: :id, product_id: :id],
      on_replace: :delete,
      where: [deleted_at: nil],
      preload_order: [asc: :name]
    )

    field(:channel_id, :string)
    field(:channel_name, :string)
    field(:events, {:array, :string}, default: [])
    field(:all_products, :boolean, default: true)
    field(:enabled, :boolean, default: true)
    field(:disabled_reason, :string)
    field(:last_error, :string)
    field(:last_error_at, :utc_datetime)

    timestamps()
  end

  @doc """
  A new subscription for a channel of `connection`'s workspace. The channel is
  chosen once: changing it later means a new subscription.
  """
  @spec create_changeset(Connection.t(), map(), ProductScope.found()) :: Ecto.Changeset.t()
  def create_changeset(%Connection{} = connection, params, products) do
    %__MODULE__{connection_id: connection.id, products: []}
    |> cast(params, [:channel_id, :channel_name])
    |> validate_required([:channel_id, :channel_name])
    |> unique_constraint([:connection_id, :channel_id], message: "already gets this organization's events")
    |> changeset(params, products)
  end

  @doc """
  The fields a person edits: which events, from which products, and whether
  it is on. `products` is what `params` named, already looked up in the
  organization (`NervesHub.Integrations.ProductScope`); the subscription's
  `products` must be loaded.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map(), ProductScope.found()) :: Ecto.Changeset.t()
  def changeset(subscription, params, products \\ nil) do
    subscription
    |> cast(params, [:events, :all_products, :enabled])
    |> validate_required([:all_products])
    |> update_change(:events, &Enum.uniq/1)
    |> validate_subset(:events, ChannelEvents.keys(), message: "contains an event that does not exist")
    |> validate_some_events()
    |> ProductScope.put(products)
    |> clear_failure_on_enable()
    |> foreign_key_constraint(:connection_id)
  end

  defp validate_some_events(changeset) do
    if get_field(changeset, :events) == [] do
      add_error(changeset, :events, "choose at least one event")
    else
      changeset
    end
  end

  defp clear_failure_on_enable(changeset) do
    if get_change(changeset, :enabled) == true do
      change(changeset, disabled_reason: nil, last_error: nil, last_error_at: nil)
    else
      changeset
    end
  end
end
