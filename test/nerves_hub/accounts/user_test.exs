defmodule NervesHub.Accounts.UserTest do
  use NervesHub.DataCase, async: true

  alias Ecto.Changeset
  alias NervesHub.Accounts
  alias NervesHub.Accounts.User
  alias NervesHub.Fixtures

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

  describe "MFA setup" do
    test "requires the current password before generating setup data" do
      user = Fixtures.user_fixture()

      assert {:error, :invalid_password} = Accounts.start_mfa_setup(user, "wrong password")
    end

    test "generates setup data and enables MFA with recovery codes after a valid TOTP code" do
      user = Fixtures.user_fixture()

      assert {:ok, setup} = Accounts.start_mfa_setup(user, "test_password")
      assert is_binary(setup.secret)
      assert setup.otpauth_uri =~ "otpauth://totp/"
      assert setup.otpauth_uri =~ "issuer=NervesHub%20"
      assert setup.otpauth_uri =~ URI.encode(NervesHubWeb.Endpoint.url(), &URI.char_unreserved?/1)
      assert setup.otpauth_uri =~ user.email
      assert setup.qr_svg =~ "<svg"
      assert is_binary(setup.manual_key)

      code = NimbleTOTP.verification_code(setup.secret)
      session_token = Accounts.create_user_session_token(user)

      assert {:ok, updated_user, recovery_codes} = Accounts.confirm_mfa_setup(user, setup.secret, code)
      assert updated_user.mfa_enabled_at
      assert updated_user.mfa_last_used_at
      assert updated_user.mfa_secret
      assert length(recovery_codes) == 10
      assert Enum.all?(recovery_codes, &String.match?(&1, ~r/^[A-Z0-9]{4}-[A-Z0-9]{4}$/))
      refute Enum.any?(updated_user.mfa_recovery_codes, fn hash -> hash in recovery_codes end)
      refute Accounts.get_user_by_session_token(session_token)
      assert {:error, :invalid_code} = Accounts.verify_mfa_code(updated_user, code)
    end
  end

  describe "MFA verification" do
    test "accepts only the current and immediately previous TOTP code" do
      user = Fixtures.user_fixture()
      {:ok, setup} = Accounts.start_mfa_setup(user, "test_password")

      {:ok, user, _recovery_codes} =
        Accounts.confirm_mfa_setup(user, setup.secret, NimbleTOTP.verification_code(setup.secret))

      now = 1_800_000_000
      current_code = NimbleTOTP.verification_code(setup.secret, time: now)
      previous_code = NimbleTOTP.verification_code(setup.secret, time: now - 30)
      older_code = NimbleTOTP.verification_code(setup.secret, time: now - 60)
      future_code = NimbleTOTP.verification_code(setup.secret, time: now + 30)

      assert {:ok, :totp} = Accounts.verify_mfa_code(user, current_code, time: now)
      user = Accounts.get_user!(user.id)
      assert {:error, :invalid_code} = Accounts.verify_mfa_code(user, current_code, time: now)

      {:ok, user} = user |> Ecto.Changeset.change(%{mfa_last_used_at: nil}) |> NervesHub.Repo.update()
      assert {:ok, :totp} = Accounts.verify_mfa_code(user, previous_code, time: now)
      assert {:error, :invalid_code} = Accounts.verify_mfa_code(user, older_code, time: now)
      assert {:error, :invalid_code} = Accounts.verify_mfa_code(user, future_code, time: now)
    end

    test "accepts a recovery code once and stores only hashes" do
      user = Fixtures.user_fixture()
      {:ok, setup} = Accounts.start_mfa_setup(user, "test_password")

      {:ok, user, [recovery_code | _]} =
        Accounts.confirm_mfa_setup(user, setup.secret, NimbleTOTP.verification_code(setup.secret))

      refute recovery_code in user.mfa_recovery_codes
      assert {:ok, :recovery_code} = Accounts.verify_mfa_code(user, recovery_code)
      user = Accounts.get_user!(user.id)
      assert {:error, :invalid_code} = Accounts.verify_mfa_code(user, recovery_code)
    end
  end
end
