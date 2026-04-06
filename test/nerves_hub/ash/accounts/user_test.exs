defmodule NervesHub.Ash.Accounts.UserTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Ash.Accounts.User
  alias NervesHub.Fixtures

  setup do
    user = Fixtures.user_fixture()
    %{user: user}
  end

  describe "read" do
    test "default read returns users", %{user: user} do
      users = User.read!()
      assert Enum.any?(users, &(&1.id == user.id))
    end

    test "get by id", %{user: user} do
      found = User.get!(user.id)
      assert found.id == user.id
      assert found.email == user.email
    end

    test "get_by_email returns matching user", %{user: user} do
      found = User.get_by_email!(user.email)
      assert found.id == user.id
    end

    test "get_by_email excludes deleted users" do
      user = Fixtures.user_fixture()
      NervesHub.Accounts.remove_account(user.id)

      assert {:error, _} = User.get_by_email(user.email)
    end
  end

  describe "create" do
    test "creates user with valid params" do
      user =
        User.create!(%{
          name: "Test User",
          email: "ash-test-#{System.unique_integer([:positive])}@test.com",
          password: "test_password"
        })

      assert user.id
      assert user.email
    end
  end

  describe "update" do
    test "updates user name", %{user: user} do
      ash_user = User.get!(user.id)
      updated = User.update!(ash_user, %{name: "New Name"})
      assert updated.name == "New Name"
    end
  end

  describe "confirm" do
    test "confirms unconfirmed user" do
      {:ok, ecto_user} =
        NervesHub.Accounts.create_user(%{
          name: "Unconfirmed",
          email: "unconfirmed-#{System.unique_integer([:positive])}@test.com",
          password: "test_password"
        })

      ash_user = User.get!(ecto_user.id)
      assert ash_user.confirmed_at == nil

      confirmed = User.confirm!(ash_user)
      assert confirmed.confirmed_at != nil
    end
  end
end
