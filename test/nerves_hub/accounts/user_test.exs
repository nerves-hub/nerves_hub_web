defmodule NervesHub.Accounts.UserTest do
  use NervesHub.DataCase
  alias Ecto.Changeset
  alias NervesHub.Accounts.User

  test "changeset/2 - validates username" do
    invalid_chars = ~w(! $ . ~ * \( \) + ; / ? : @ = & " < > # % { } | \ ^ [ ] \s`)

    Enum.each(invalid_chars, fn char ->
      %Changeset{errors: errors} =
        User.creation_changeset(%NervesHub.Accounts.User{}, %{username: "username#{char}"})

      assert {"invalid character(s) in username", []} = errors[:username]
    end)

    %Changeset{errors: errors} =
      User.creation_changeset(%NervesHub.Accounts.User{}, %{
        username: "1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_"
      })

    assert is_nil(errors[:username])
  end
end
