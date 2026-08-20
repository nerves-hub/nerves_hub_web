defmodule NervesHub.Accounts.UserTest do
  use NervesHub.DataCase, async: true

  alias Ecto.Changeset
  alias NervesHub.Accounts.User

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
end
