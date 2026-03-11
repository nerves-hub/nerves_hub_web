defmodule NervesHubWeb.Live.Product.NotificationsTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.Scope
  alias NervesHub.Fixtures
  alias NervesHub.Products.Notification

  test "only notifications for the product being viewed can be dismissed", %{conn: conn, org: org, user: user} do
    product = Fixtures.product_fixture(user, org)
    other_product = Fixtures.product_fixture(user, org)

    NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
      product.id,
      "abc",
      :shared_secrets
    )

    NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
      other_product.id,
      "abc",
      :shared_secrets
    )

    assert NervesHub.Repo.aggregate(Notification, :count) == 2

    conn
    |> visit("/org/#{org.name}/#{product.name}/notifications")
    |> assert_has("h1", text: "Notifications")
    |> assert_has("div", text: "A device failed connecting as the identifier 'abc' already exists.")
    |> click_button("Dismiss all")
    |> assert_has("div", text: "All notifications have been dismissed")
    |> refute_has("div", text: "A device failed connecting as the identifier 'abc' already exists.")

    assert NervesHub.Repo.aggregate(Notification, :count) == 1
  end

  test "the notification list is refreshed if someone else dismisses all notifications", %{
    conn: conn,
    org: org,
    user: user
  } do
    product = Fixtures.product_fixture(user, org)

    other_user = Fixtures.user_fixture()
    _ = NervesHub.Accounts.add_org_user(org, other_user, %{role: :manage})

    NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
      product.id,
      "abc",
      :shared_secrets
    )

    assert NervesHub.Repo.aggregate(Notification, :count) == 1

    conn
    |> visit("/org/#{org.name}/#{product.name}/notifications")
    |> assert_has("h1", text: "Notifications")
    |> assert_has("div", text: "A device failed connecting as the identifier 'abc' already exists.")
    |> tap(fn _ ->
      scope = Scope.for_user(other_user) |> Scope.put_product(product)
      NervesHub.ProductNotifications.delete_all(scope)
    end)
    |> assert_has("div", text: "All notifications have been dismissed by #{other_user.name}", exact: false)
    |> refute_has("div", text: "A device failed connecting as the identifier 'abc' already exists.")

    assert NervesHub.Repo.aggregate(Notification, :count) == 0
  end

  test "a user with :view role can't dismiss notifications", %{conn: conn, org: org, user: user} do
    product = Fixtures.product_fixture(user, org)

    NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
      product.id,
      "abc",
      :shared_secrets
    )

    NervesHub.Repo.update_all(OrgUser, set: [role: :view])

    assert NervesHub.Repo.aggregate(Notification, :count) == 1

    conn =
      conn
      |> visit("/org/#{org.name}/#{product.name}/notifications")
      |> assert_has("h1", text: "Notifications")
      |> assert_has("div", text: "A device failed connecting as the identifier 'abc' already exists.")
      |> refute_has("button", text: "Dismiss all")

    Process.flag(:trap_exit, true)

    assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} =
             catch_exit(render_click(conn.view, "dismiss-all", %{}))

    assert NervesHub.Repo.aggregate(Notification, :count) == 1
  end

  describe "pagination" do
    test "if you are viewing the first page, the notifcation list is refreshed if a new notification is created",
         %{
           conn: conn,
           org: org,
           user: user
         } do
      product = Fixtures.product_fixture(user, org)

      for n <- 1..30 do
        updated_loa = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-n, :minute)

        NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
          product.id,
          "abc-#{n}",
          :shared_secrets
        )
        |> Ecto.Changeset.change(last_occurred_at: updated_loa)
        |> NervesHub.Repo.update()
      end

      assert NervesHub.Repo.aggregate(Notification, :count) == 30

      conn
      |> visit("/org/#{org.name}/#{product.name}/notifications")
      |> assert_has("h1", text: "Notifications")
      |> assert_has("div#notification-count", text: "30")
      |> assert_has("div", text: "A device failed connecting as the identifier 'abc-1' already exists.")
      |> assert_has("div", text: "A device failed connecting as the identifier 'abc-25' already exists.")
      |> tap(fn _ ->
        NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
          product.id,
          "snootboop",
          :shared_secrets
        )
      end)
      |> assert_has("div#notification-count", text: "31")
      |> assert_has("div", text: "New notification is available")
      |> assert_has("div",
        text: "A device failed connecting as the identifier 'snootboop' already exists.",
        timeout: 1000
      )
      |> refute_has("div", text: "A device failed connecting as the identifier 'abc-25' already exists.")

      assert NervesHub.Repo.aggregate(Notification, :count) == 31
    end

    test "if you are viewing the second page, the notifcation list is not refreshed if a new notification is created",
         %{
           conn: conn,
           org: org,
           user: user
         } do
      product = Fixtures.product_fixture(user, org)

      for n <- 1..30 do
        updated_loa = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-n, :minute)

        NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
          product.id,
          "abc-#{n}",
          :shared_secrets
        )
        |> Ecto.Changeset.change(last_occurred_at: updated_loa)
        |> NervesHub.Repo.update()
      end

      assert NervesHub.Repo.aggregate(Notification, :count) == 30

      conn
      |> visit("/org/#{org.name}/#{product.name}/notifications")
      |> assert_has("h1", text: "Notifications")
      |> assert_has("div#notification-count", text: "30")
      |> assert_has("div", text: "A device failed connecting as the identifier 'abc-1' already exists.")
      |> assert_has("div", text: "A device failed connecting as the identifier 'abc-25' already exists.")
      |> click_button(".pager-button[phx-click=\"paginate\"]", "2")
      |> assert_has("div", text: "A device failed connecting as the identifier 'abc-26' already exists.")
      |> assert_has("div", text: "A device failed connecting as the identifier 'abc-30' already exists.")
      |> tap(fn _ ->
        NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
          product.id,
          "snootboop",
          :shared_secrets
        )
      end)
      |> assert_has("div#notification-count", text: "31")
      |> assert_has("div", text: "New notification is available. Please view the 1st page to see it.")
      |> refute_has("div",
        text: "A device failed connecting as the identifier 'snootboop' already exists.",
        timeout: 1000
      )

      assert NervesHub.Repo.aggregate(Notification, :count) == 31
    end

    test "you can select the number of notifications per page",
         %{
           conn: conn,
           org: org,
           user: user
         } do
      product = Fixtures.product_fixture(user, org)

      for n <- 1..30 do
        updated_loa = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-n, :minute)

        NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
          product.id,
          "abc-#{n}",
          :shared_secrets
        )
        |> Ecto.Changeset.change(last_occurred_at: updated_loa)
        |> NervesHub.Repo.update()
      end

      assert NervesHub.Repo.aggregate(Notification, :count) == 30

      conn
      |> visit("/org/#{org.name}/#{product.name}/notifications")
      |> assert_has("h1", text: "Notifications")
      |> assert_has("div#notification-count", text: "30")
      |> assert_has("div", text: "A device failed connecting as the identifier 'abc-1' already exists.")
      |> assert_has("div", text: "A device failed connecting as the identifier 'abc-25' already exists.")
      |> click_button(".pager-button[phx-click=\"set-paginate-opts\"]", "50")
      |> assert_has("div", text: "A device failed connecting as the identifier 'abc-1' already exists.")
      |> assert_has("div", text: "A device failed connecting as the identifier 'abc-30' already exists.")
    end
  end
end
