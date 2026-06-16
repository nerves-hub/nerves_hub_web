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

  @spec create_device_async_bulk_create_notification!(
          product_id :: pos_integer(),
          successfully_created_count :: non_neg_integer(),
          unsuccessfully_created_count :: non_neg_integer(),
          format :: String.t()
        ) :: Notification.t()
  def create_device_async_bulk_create_notification!(
        product_id,
        successfully_created_count,
        unsuccessfully_created_count,
        format
      ) do
    [message, level] =
      case {successfully_created_count, unsuccessfully_created_count} do
        {0, 0} ->
          [
            "No devices entries were processed. Please check if the uploaded manifest was empty, or contact support if you believe this was an error with the import process.",
            :warning
          ]

        {1, 0} ->
          [
            "1 device was imported successfully. Only 1 device was detected in the manifest, please contact support if this was incorrect.",
            :info
          ]

        {successful_count, 0} ->
          [
            "All device entries were imported successfully. #{successful_count} devices have been created, along with their associated certificates.",
            :info
          ]

        {0, unsuccessful_count} ->
          [
            "All device entries (#{unsuccessful_count}) failed to import successfully. Please check if the uploaded manifest was valid, or contact support if you believe this was an error with the import process.",
            :error
          ]

        {successful_count, unsuccessful_count} ->
          [
            "#{successful_count} device#{if(successful_count > 1, do: "s")} were imported successfully, and #{unsuccessful_count} device#{if(unsuccessful_count > 1, do: "s")} failed to import. Please check if the uploaded manifest was valid, or contact support if you believe this was an error with the import process.",
            :warning
          ]
      end

    Products.get_product!(product_id)
    |> Notification.new_changeset(%{
      title: "An async bulk device import has completed.",
      message: message,
      level: level,
      metadata: %{format: format},
      event_key: "device_bulk_create-#{DateTime.utc_now() |> DateTime.to_unix()}"
    })
    |> insert_and_notify!()
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

  def count(product) do
    Notification
    |> where(product_id: ^product.id)
    |> Repo.aggregate(:count)
  end
end
