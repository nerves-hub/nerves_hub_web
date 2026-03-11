defmodule NervesHub.Products.Notification do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Products.Product

  @type t :: %__MODULE__{}

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "product_notifications" do
    belongs_to(:product, Product)

    field(:title, :string)
    field(:message, :string)
    field(:metadata, :map)
    field(:level, Ecto.Enum, values: [:info, :warning, :error])

    field(:event_key, :string)
    field(:last_occurred_at, :utc_datetime)
    field(:occurrence_count, :integer, default: 1)

    timestamps()
  end

  def new_changeset(product, params) do
    %__MODULE__{}
    |> cast(params, [:title, :message, :metadata, :level, :event_key])
    |> put_change(:product_id, product.id)
    |> put_change(:last_occurred_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> update_change(:event_key, &String.trim/1)
    |> validate_required([:product_id, :title, :message, :metadata, :level, :event_key])
    |> validate_change(:event_key, fn _, value ->
      if String.contains?(value, " ") do
        [event_key: "cannot contain spaces"]
      else
        []
      end
    end)
  end
end
