defmodule NervesHub.MFATest do
  use NervesHub.DataCase, async: true

  alias NervesHub.MFA
  alias NervesHub.Fixtures

  describe "user_totps" do
    alias NervesHub.MFA.UserTOTP

    setup do
      user = Fixtures.user_fixture()
      secret = Base.decode32!("PTEPUGZ7DUWTBGMW4WLKB6U63MGKKMCA")
      totp = %UserTOTP{user_id: user.id, secret: secret}
      %{user: user, totp: totp, secret: secret}
    end

    test "validates required otp", %{totp: totp} do
      {:error, changeset} = MFA.upsert_user_totp(totp, %{code: ""})
      assert %{code: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates otp as 6 digits number", %{totp: totp} do
      {:error, changeset} = MFA.upsert_user_totp(totp, %{code: "1234567"})
      assert %{code: ["should be a 6 digit number"]} = errors_on(changeset)
    end

    test "validates otp against the secret", %{totp: totp} do
      {:error, changeset} = MFA.upsert_user_totp(totp, %{code: "123456"})
      assert %{code: ["invalid code"]} = errors_on(changeset)
    end

    test "upserts user's TOTP secret", %{totp: totp, user: _user, secret: secret} do
      otp = NimbleTOTP.verification_code(totp.secret)

      assert {:ok, totp} = MFA.upsert_user_totp(totp, %{code: otp})
      assert Repo.get!(UserTOTP, totp.id).secret == totp.secret

      new_otp = NimbleTOTP.verification_code(secret)

      assert {:ok, _} =
               MFA.upsert_user_totp(%{totp | secret: secret}, %{
                 code: new_otp
               })
    end

    test "generates backup codes if they are missing", %{totp: totp, user: _user} do
      otp = NimbleTOTP.verification_code(totp.secret)

      assert {:ok, totp} = MFA.upsert_user_totp(totp, %{code: otp})

      assert length(totp.backup_codes) == 10
      assert Enum.all?(totp.backup_codes, &(byte_size(&1.code) == 8))
      assert Enum.all?(totp.backup_codes, &(:binary.first(&1.code) in ?A..?Z))
    end

    test "removes otp secret", %{user: user} do
      totp = Fixtures.user_totp_fixture(%{user_id: user.id})
      :ok = MFA.delete_user_totp(totp)
      refute Repo.get(UserTOTP, totp.id)
    end

    test "replaces backup codes", %{user: user} do
      totp = Fixtures.user_totp_fixture(%{user_id: user.id})
      assert MFA.regenerate_user_totp_backup_codes(totp).backup_codes != totp.backup_codes
    end

    test "does not persist changes made to the struct", %{user: user} do
      totp = Fixtures.user_totp_fixture(%{user_id: user.id})
      changed = %{totp | secret: "SECRET"}
      assert MFA.regenerate_user_totp_backup_codes(changed).secret == "SECRET"
      assert Repo.get(UserTOTP, changed.id).secret == totp.secret
    end

    test "returns invalid if the code is not valid", %{user: user} do
      _totp = Fixtures.user_totp_fixture(%{user_id: user.id})
      assert MFA.validate_user_totp(user, "invalid") == :invalid
      assert MFA.validate_user_totp(user, nil) == :invalid
    end

    test "returns valid for valid totp", %{user: user} do
      totp = Fixtures.user_totp_fixture(%{user_id: user.id})
      code = NimbleTOTP.verification_code(totp.secret)
      assert MFA.validate_user_totp(user, code) == :valid_totp
    end

    test "returns valid for valid backup code", %{user: user} do
      totp = Fixtures.user_totp_fixture(%{user_id: user.id})
      at = :rand.uniform(10) - 1
      code = Enum.fetch!(totp.backup_codes, at).code
      assert MFA.validate_user_totp(user, code) == {:valid_backup_code, 9}
      assert Enum.fetch!(Repo.get(UserTOTP, totp.id).backup_codes, at).used_at

      # Cannot reuse the code
      assert MFA.validate_user_totp(user, code) == :invalid
    end
  end
end
