defmodule NervesHub.ProductNotifications do
  import Ecto.Query

  alias NervesHub.Accounts.Scope
  alias NervesHub.Devices.Device
  alias NervesHub.Products
  alias NervesHub.Products.Notification
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias Phoenix.Channel.Server
  alias Phoenix.PubSub

  @spec subscribe(pos_integer()) :: :ok
  def subscribe(product_id) do
    _ = PubSub.subscribe(NervesHub.PubSub, "product_notifications:#{product_id}")
    :ok
  end

  @spec paginated_list(Product.t(), integer(), integer()) :: {[Notification.t()], Flop.Meta.t()}
  def paginated_list(%Product{} = product, page \\ 1, page_size \\ 25) do
    flop = %Flop{page: page, page_size: page_size}

    Notification
    |> where([n], n.product_id == ^product.id)
    |> order_by(desc: :last_occurred_at)
    |> Flop.run(flop)
  end

  @spec delete_all(Scope.t()) :: :ok
  def delete_all(%Scope{product: product, user: user}) do
    _ =
      Notification
      |> where([n], n.product_id == ^product.id)
      |> Repo.delete_all()

    _ =
      Server.broadcast(
        NervesHub.PubSub,
        "product_notifications:#{product.id}",
        "dismissed",
        %{dismissed_by: %{id: user.id, name: user.name}}
      )

    :ok
  end

  @spec create_duplicate_device_identifier_notification!(
          product_id :: pos_integer(),
          identifier :: String.t(),
          auth_type :: atom()
        ) :: Notification.t()
  def create_duplicate_device_identifier_notification!(product_id, identifier, auth_type) do
    Products.get_product!(product_id)
    |> Notification.new_changeset(%{
      title: "A device failed connecting as the identifier '#{identifier}' already exists.",
      message: "Please check if you have any soft deleted devices, or choose another identifier for the device.",
      level: :warning,
      metadata: %{identifier: identifier, auth_type: auth_type},
      event_key: "duplicate_device_identifier-#{identifier}"
    })
    |> insert_and_notify!()
  end

  @spec create_soft_deleted_device_removed!(device :: Device.t()) :: Notification.t()
  def create_soft_deleted_device_removed!(device) do
    %Product{id: device.product_id}
    |> Notification.new_changeset(%{
      title: "A soft-deleted device with the identifier '#{device.identifier}' has been permanently deleted.",
      message: "Soft deleted devices are permanently deleted after two weeks.",
      level: :info,
      metadata: %{identifier: device.identifier},
      event_key: "soft_deleted_device-#{device.identifier}"
    })
    |> insert_and_notify!()
  end

  defp insert_and_notify!(changeset) do
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
        conflict_target: [:product_id, :event_key]
      )

    _ =
      Server.broadcast(
        NervesHub.PubSub,
        "product_notifications:#{notification.product_id}",
        "created",
        %{}
      )

    notification
  end
end
