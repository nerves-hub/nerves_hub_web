defmodule NervesHub.Accounts.UserTest do
  use NervesHub.DataCase, async: true

  import Ecto.Query

  alias Ecto.Changeset
  alias NervesHub.Accounts.User
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  test "changeset/2 - validates username" do
    invalid_chars = ~w(! $ . ~ * \( \) + ; / ? : @ = & " < > # % { } | \ ^ [ ] \s`)

    Enum.each(invalid_chars, fn char ->
      %Changeset{errors: errors} =
        User.creation_changeset(%User{}, %{name: "Name#{char}"})

      assert {"has invalid character(s)", [{:validation, :format}]} = errors[:name]
    end)

    %Changeset{errors: errors} =
      User.creation_changeset(%User{}, %{
        name: "1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_"
      })

    assert is_nil(errors[:username])
  end

  describe "registration_changeset/3 - name" do
    @valid_attrs %{email: "user@example.com", password: "supersecretpassword"}

    test "rejects names containing a web address" do
      for name <- ["Buy now at example.com", "https://spam.io", "www.spam.ru", "check spam.xyz out"] do
        changeset = User.registration_changeset(%User{}, Map.put(@valid_attrs, :name, name))

        refute changeset.valid?, "expected #{name} to be rejected"
        assert changeset.errors[:name]
      end
    end

    test "rejects names containing markup or url punctuation" do
      for name <- ["<a href=x>hi</a>", "Name/Other", "Name@Host", "Call 555"] do
        changeset = User.registration_changeset(%User{}, Map.put(@valid_attrs, :name, name))

        refute changeset.valid?, "expected #{name} to be rejected"
        assert {"has invalid character(s)", _} = changeset.errors[:name]
      end
    end

    test "accepts ordinary names" do
      for name <- ["Jane Doe", "Anne-Marie O'Brien", "José Álvarez", "Ólafur Þór"] do
        changeset = User.registration_changeset(%User{}, Map.put(@valid_attrs, :name, name))

        assert changeset.valid?, "expected #{name} to be accepted"
      end
    end
  end

  test "maybe_add_confirmed_at skips already-confirmed user" do
    user = Fixtures.user_fixture()
    # user is already confirmed; oauth_changeset should not override confirmed_at
    google_auth = Fixtures.ueberauth_google_success_fixture()
    changeset = User.oauth_changeset(user, google_auth)
    refute Map.has_key?(changeset.changes, :confirmed_at)
  end

  test "valid_password?/2 calls no_user_verify when no password hash" do
    # Should return false and not crash
    result = User.valid_password?(%User{}, "somepassword")
    assert result == false
  end

  test "with_all_orgs/1 preloads orgs on a User struct" do
    user = Fixtures.user_fixture()
    loaded = User.with_all_orgs(user)
    assert is_list(loaded.orgs)
  end

  test "with_all_orgs/1 preloads orgs on a query" do
    user = Fixtures.user_fixture()
    query = User |> where([u], u.id == ^user.id) |> User.with_all_orgs()
    [loaded] = Repo.all(query)
    assert is_list(loaded.orgs)
  end

  test "with_org_keys/1 preloads org_keys on a User struct" do
    user = Fixtures.user_fixture()
    _org = Fixtures.org_fixture(user)
    loaded = User.with_org_keys(user)
    assert is_list(loaded.orgs)
    assert is_list(hd(loaded.orgs).org_keys)
  end

  test "with_org_keys/1 preloads org_keys on a query" do
    user = Fixtures.user_fixture()
    _org = Fixtures.org_fixture(user)
    query = User |> where([u], u.id == ^user.id) |> User.with_org_keys()
    [loaded] = Repo.all(query)
    assert is_list(loaded.orgs)
  end

  test "password_reset_window/0 returns a keyword list" do
    window = User.password_reset_window()
    assert is_list(window)
    assert Keyword.keyword?(window)
  end

  test "update_changeset/2 with wrong current_password adds error" do
    user = Fixtures.user_fixture()

    changeset =
      User.update_changeset(user, %{
        "email" => "changed@example.com",
        "current_password" => "wrongpassword"
      })

    assert changeset.errors[:current_password] != nil
  end

  test "update_changeset/2 changing email without current_password adds error" do
    user = Fixtures.user_fixture()

    changeset =
      User.update_changeset(user, %{"email" => "changed@example.com"})

    assert changeset.errors[:current_password] != nil
  end

  test "update_changeset/2 no email/password change with current_password does not add error" do
    user = Fixtures.user_fixture()

    changeset =
      User.update_changeset(user, %{
        "current_password" => "somepassword"
      })

    assert changeset.errors[:current_password] == nil
  end

  test "changeset/2 with nil name passes nil through trim fallback" do
    changeset = User.creation_changeset(%User{}, %{name: nil, email: "a@b.com", password: "longenoughpassword"})
    refute changeset.valid?
  end
end
