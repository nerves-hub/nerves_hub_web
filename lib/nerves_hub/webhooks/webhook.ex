defmodule NervesHub.Webhooks.Webhook do
  @moduledoc """
  An HTTP endpoint an organization sends a chosen set of device events to.

  A webhook hears from every product in the organization (`all_products`), or
  only from the products it lists in `products`. Products added later are
  covered by the first and not the second.

  `secret` signs every delivery (see `NervesHub.Webhooks.Signature`). It is
  generated here rather than chosen by the user, so it always has the length
  and format the Standard Webhooks libraries a receiver verifies with expect.

  `failing_since`, `last_error` and `last_error_at` describe the endpoint as
  deliveries have found it, and are written by the delivery worker rather than
  by anyone editing the webhook. `disabled_reason` is set when deliveries
  turned the webhook off, and cleared when a person turns it back on.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.Org
  alias NervesHub.Products.Product
  alias NervesHub.Webhooks.Destination
  alias NervesHub.Webhooks.Events
  alias NervesHub.Webhooks.Signature

  @type t :: %__MODULE__{}

  @max_url_length 2048

  schema "webhooks" do
    belongs_to(:org, Org)

    many_to_many(:products, Product,
      join_through: "webhook_products",
      on_replace: :delete,
      where: [deleted_at: nil],
      preload_order: [asc: :name]
    )

    field(:url, :string)
    field(:description, :string)
    field(:secret, :string, redact: true)
    field(:events, {:array, :string}, default: [])
    field(:all_products, :boolean, default: true)
    field(:enabled, :boolean, default: true)
    field(:disabled_reason, :string)
    field(:failing_since, :utc_datetime)
    field(:last_error, :string)
    field(:last_error_at, :utc_datetime)

    timestamps()
  end

  @typedoc """
  The products a change names, as `NervesHub.Webhooks` found them in the
  organization: those it found, and the names it did not. `nil` when the
  change names no products, which leaves them as they are.
  """
  @type products() :: {[Product.t()], [String.t()]} | :invalid | nil

  @doc """
  A new webhook for `org`, with a freshly generated signing secret.
  """
  @spec create_changeset(Org.t(), map(), products()) :: Ecto.Changeset.t()
  def create_changeset(%Org{} = org, params, products) do
    %__MODULE__{org_id: org.id, products: [], secret: Signature.generate_secret()}
    |> changeset(params, products)
  end

  @doc """
  The fields a person edits: where deliveries go, what they are for, which
  events they carry, and which products they come from.

  `products` is what `params` named, already looked up in the organization
  (see `t:products/0`), since a changeset cannot query. The webhook's
  `products` must be loaded.

  Turning a webhook on clears what deliveries recorded about it, so it starts
  from a clean slate rather than looking broken because of failures that were
  the reason somebody fixed and re-enabled it.
  """
  @spec changeset(t(), map(), products()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = webhook, params, products \\ nil) do
    webhook
    |> cast(params, [:url, :description, :events, :all_products, :enabled])
    |> update_change(:url, &String.trim/1)
    |> update_change(:description, &String.trim/1)
    |> validate_required([:url, :all_products])
    |> validate_length(:url, max: @max_url_length)
    |> validate_length(:description, max: 255)
    |> validate_url()
    |> validate_events()
    |> put_product_scope(products)
    |> clear_delivery_state_on_enable()
    |> foreign_key_constraint(:org_id)
  end

  @doc """
  Replaces the signing secret. The old one stops working at once.
  """
  @spec regenerate_secret_changeset(t()) :: Ecto.Changeset.t()
  def regenerate_secret_changeset(%__MODULE__{} = webhook) do
    change(webhook, secret: Signature.generate_secret())
  end

  defp validate_url(changeset) do
    validate_change(changeset, :url, fn :url, url ->
      case Destination.validate_url(url) do
        :ok -> []
        {:error, message} -> [url: message]
      end
    end)
  end

  defp validate_events(changeset) do
    changeset
    |> update_change(:events, &Enum.uniq/1)
    |> validate_subset(:events, Events.types(), message: "contains an event that does not exist")
    |> validate_some_events()
  end

  # The field rather than the change: a new webhook's events default to `[]`,
  # so submitting none is no change at all, and `validate_length/3` would let
  # it through.
  defp validate_some_events(changeset) do
    if get_field(changeset, :events) == [] do
      add_error(changeset, :events, "choose at least one event")
    else
      changeset
    end
  end

  # A webhook for every product keeps no list, so that limiting it later
  # starts from an empty choice rather than a forgotten one, and names the
  # change carries are not looked at.
  defp put_product_scope(changeset, products) do
    if get_field(changeset, :all_products) do
      put_assoc(changeset, :products, [])
    else
      changeset
      |> put_products(products)
      |> require_products()
    end
  end

  defp put_products(changeset, nil), do: changeset
  defp put_products(changeset, :invalid), do: add_error(changeset, :products, "must be a list of product names")
  defp put_products(changeset, {products, []}), do: put_assoc(changeset, :products, products)

  defp put_products(changeset, {_products, unknown}) do
    add_error(changeset, :products, "has no product named #{Enum.join(unknown, ", ")}")
  end

  defp require_products(changeset) do
    if is_nil(changeset.errors[:products]) and get_field(changeset, :products) == [] do
      add_error(changeset, :products, "choose at least one product")
    else
      changeset
    end
  end

  defp clear_delivery_state_on_enable(changeset) do
    if get_change(changeset, :enabled) == true do
      change(changeset, disabled_reason: nil, failing_since: nil, last_error: nil, last_error_at: nil)
    else
      changeset
    end
  end
end
