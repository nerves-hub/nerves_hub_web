defmodule NervesHub.Webhooks.Webhook do
  @moduledoc """
  An HTTP endpoint a product sends a chosen set of device events to.

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

  alias NervesHub.Products.Product
  alias NervesHub.Webhooks.Destination
  alias NervesHub.Webhooks.Events
  alias NervesHub.Webhooks.Signature

  @type t :: %__MODULE__{}

  @max_url_length 2048

  schema "product_webhooks" do
    belongs_to(:product, Product)

    field(:url, :string)
    field(:description, :string)
    field(:secret, :string, redact: true)
    field(:events, {:array, :string}, default: [])
    field(:enabled, :boolean, default: true)
    field(:disabled_reason, :string)
    field(:failing_since, :utc_datetime)
    field(:last_error, :string)
    field(:last_error_at, :utc_datetime)

    timestamps()
  end

  @doc """
  A new webhook for `product`, with a freshly generated signing secret.
  """
  @spec create_changeset(Product.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(%Product{} = product, params) do
    %__MODULE__{product_id: product.id, secret: Signature.generate_secret()}
    |> changeset(params)
  end

  @doc """
  The fields a person edits: where deliveries go, what they are for, and which
  events they carry.

  Turning a webhook on clears what deliveries recorded about it, so it starts
  from a clean slate rather than looking broken because of failures that were
  the reason somebody fixed and re-enabled it.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = webhook, params) do
    webhook
    |> cast(params, [:url, :description, :events, :enabled])
    |> update_change(:url, &String.trim/1)
    |> update_change(:description, &String.trim/1)
    |> validate_required([:url])
    |> validate_length(:url, max: @max_url_length)
    |> validate_length(:description, max: 255)
    |> validate_url()
    |> validate_events()
    |> clear_delivery_state_on_enable()
    |> foreign_key_constraint(:product_id)
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

  defp clear_delivery_state_on_enable(changeset) do
    if get_change(changeset, :enabled) == true do
      change(changeset, disabled_reason: nil, failing_since: nil, last_error: nil, last_error_at: nil)
    else
      changeset
    end
  end
end
