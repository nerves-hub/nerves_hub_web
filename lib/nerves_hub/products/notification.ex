defmodule NervesHub.Products.Notification do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Products.Product

  # What happened, so the web UI can write each notification for where it's
  # shown, roll a fleet's worth of one problem into a card, and link what it's
  # about. The event key starts with it. Rows written before kinds existed
  # were given one from their key; one that couldn't be has none, and is shown
  # with the title and message it was stored with.
  #
  # Ecto.Enum won't load a value it doesn't list, so a node still on an older
  # release fails to read a notification with a kind added after it. Add a
  # kind in one release and start writing it in the next.
  @kinds [
    :chat_webhook_disabled,
    :connecting_code_failure,
    :device_bulk_create,
    :duplicate_device_identifier,
    :extension_failure,
    :missing_firmware_metadata,
    :oversized_metric_keys,
    :slack_subscription_disabled,
    :soft_deleted_device,
    :too_many_metrics,
    :update_mode_revert_failed,
    :webhook_disabled,
    :workflow_halted,
    :wrong_websocket_host
  ]

  # Kinds raised per device, which a problem across the fleet raises for
  # every device it hits. The list shows each as one card holding its devices.
  @device_kinds [
    :duplicate_device_identifier,
    :extension_failure,
    :missing_firmware_metadata,
    :oversized_metric_keys,
    :soft_deleted_device,
    :too_many_metrics,
    :update_mode_revert_failed,
    :wrong_websocket_host
  ]

  @type t :: %__MODULE__{}
  @type level :: :info | :warning | :error
  @type kind :: unquote(Enum.reduce(Enum.reverse(@kinds), &{:|, [], [&1, &2]}))
  @type device_kind :: unquote(Enum.reduce(Enum.reverse(@device_kinds), &{:|, [], [&1, &2]}))

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  schema "product_notifications" do
    belongs_to(:product, Product)

    field(:kind, Ecto.Enum, values: @kinds)
    field(:title, :string)
    field(:message, :string)
    field(:metadata, :map)
    field(:level, Ecto.Enum, values: [:info, :warning, :error])

    field(:event_key, :string)
    field(:last_occurred_at, :utc_datetime)
    field(:occurrence_count, :integer, default: 1)

    timestamps()
  end

  @doc "Every kind of notification."
  @spec kinds() :: nonempty_list(kind())
  def kinds(), do: @kinds

  @doc """
  The kinds raised per device, which the notifications list rolls up into
  one card per kind.
  """
  @spec device_kinds() :: nonempty_list(device_kind())
  def device_kinds(), do: @device_kinds

  def new_changeset(product, params) do
    %__MODULE__{}
    |> cast(params, [:kind, :title, :message, :metadata, :level, :event_key])
    |> put_change(:product_id, product.id)
    |> put_change(:last_occurred_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> validate_required([:product_id, :kind, :title, :message, :metadata, :level, :event_key])
  end
end
