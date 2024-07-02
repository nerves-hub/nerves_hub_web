defmodule NervesHub.Accounts.UserTest do
  use NervesHub.DataCase
  alias Ecto.Changeset
  alias NervesHub.Accounts.User

  test "changeset/2 - validates username" do
    invalid_chars = ~w(! $ . ~ * \( \) + ; / ? : @ = & " < > # % { } | \ ^ [ ] \s`)

    Enum.each(invalid_chars, fn char ->
      %Changeset{errors: errors} =
        User.creation_changeset(%NervesHub.Accounts.User{}, %{name: "Name#{char}"})

      assert {"invalid character(s) in name", []} = errors[:name]
    end)

    %Changeset{errors: errors} =
      User.creation_changeset(%NervesHub.Accounts.User{}, %{
        name: "1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_"
      })

    assert is_nil(errors[:username])
  end
end
