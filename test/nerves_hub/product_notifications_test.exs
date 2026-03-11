defmodule NervesHub.ProductNotificationsTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Accounts.Scope
  alias NervesHub.Fixtures
  alias NervesHub.Products.Notification
  alias Phoenix.Socket.Broadcast

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)

    %{user: user, org: org, product: product}
  end

  test "can paginate through notifications", %{user: user, org: org, product: product} do
    other_product = Fixtures.product_fixture(user, org)

    for n <- 1..30 do
      NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
        product.id,
        "abc-#{n}",
        :shared_secrets
      )
    end

    for n <- 1..30 do
      NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
        other_product.id,
        "abc-#{n}",
        :shared_secrets
      )
    end

    notifications = Repo.all(Notification)

    assert length(notifications) == 60

    {_list, meta} = NervesHub.ProductNotifications.paginated_list(product)

    assert meta.total_pages == 2
    assert meta.total_count == 30
  end

  test "all notifications for a product can be dismissed", %{user: user, org: org, product: product} do
    other_product = Fixtures.product_fixture(user, org)

    NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(product.id, "abc", :shared_secrets)

    NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
      other_product.id,
      "abc",
      :shared_secrets
    )

    notifications = Repo.all(Notification)

    assert length(notifications) == 2

    Scope.for_user(user)
    |> Scope.put_product(product)
    |> NervesHub.ProductNotifications.delete_all()

    notifications = Repo.all(Notification)

    assert length(notifications) == 1
  end

  test "if a notification already exists for a given key, its last_occurrence is updated and occurrence_count is incremented",
       %{product: product} do
    NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(product.id, "abc", :shared_secrets)
    NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(product.id, "abc", :shared_secrets)
    NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(product.id, "abc", :shared_secrets)

    notifications = Repo.all(Notification)

    assert length(notifications) == 1

    notification = notifications |> hd()

    assert notification |> Map.get(:title) == "A device failed connecting as the identifier 'abc' already exists."
    assert notification |> Map.get(:occurrence_count) == 3
  end

  test "a broadcast is sent to the product's channel when a notification is created",
       %{product: product} do
    NervesHub.ProductNotifications.subscribe(product.id)
    NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(product.id, "abc", :shared_secrets)
    assert_receive %Broadcast{event: "created"}
  end
end
