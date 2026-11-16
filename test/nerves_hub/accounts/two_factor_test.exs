defmodule NervesHub.Accounts.TwoFactorTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Accounts
  alias NervesHub.Accounts.TwoFactor
  alias NervesHub.Accounts.UserTOTP
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  setup do
    user = Fixtures.user_fixture()
    %{user: user}
  end

  describe "enable/3" do
    test "turns it on once a code from the app matches", %{user: user} do
      secret = TwoFactor.new_secret()

      assert {:ok, codes} = TwoFactor.enable(user, secret, NimbleTOTP.verification_code(secret))
      assert length(codes) == 10
      assert Enum.all?(codes, &String.match?(&1, ~r/\A[a-z2-7]{5}-[a-z2-7]{5}\z/))
      assert TwoFactor.enabled?(user)
    end

    test "stores the secret encrypted and only hashes of the recovery codes", %{user: user} do
      %{secret: secret, recovery_codes: codes} = Fixtures.two_factor_fixture(user)

      {:ok, %{rows: [[stored_secret, stored_codes]]}} =
        Repo.query("SELECT secret, recovery_codes FROM user_totps WHERE user_id = $1", [user.id])

      assert :binary.match(stored_secret, secret) == :nomatch
      refute Enum.any?(codes, &(&1 in stored_codes))
    end

    test "refuses a wrong code and stores nothing", %{user: user} do
      secret = TwoFactor.new_secret()

      assert {:error, :invalid_code} = TwoFactor.enable(user, secret, "000000")
      refute TwoFactor.enabled?(user)
    end

    test "refuses to set up a second app", %{user: user} do
      Fixtures.two_factor_fixture(user)
      secret = TwoFactor.new_secret()

      assert {:error, :already_enabled} = TwoFactor.enable(user, secret, NimbleTOTP.verification_code(secret))
    end
  end

  describe "verify/2" do
    setup %{user: user}, do: Fixtures.two_factor_fixture(user)

    test "accepts a code from the app", %{user: user, secret: secret} do
      assert {:ok, :totp} = TwoFactor.verify(user, Fixtures.next_totp_code(secret))
    end

    test "ignores spaces in a code", %{user: user, secret: secret} do
      <<first::binary-3, last::binary-3>> = Fixtures.next_totp_code(secret)

      assert {:ok, :totp} = TwoFactor.verify(user, "#{first} #{last}")
    end

    test "accepts each period's code only once", %{user: user, secret: secret} do
      code = Fixtures.next_totp_code(secret)

      assert {:ok, :totp} = TwoFactor.verify(user, code)
      assert {:error, :invalid_code} = TwoFactor.verify(user, code)
    end

    test "won't take an earlier period's code once a later one was used", %{user: user, secret: secret} do
      assert {:ok, :totp} = TwoFactor.verify(user, Fixtures.next_totp_code(secret))
      assert {:error, :invalid_code} = TwoFactor.verify(user, NimbleTOTP.verification_code(secret))
    end

    test "won't take the code that turned it on", %{user: user, enable_code: enable_code} do
      assert {:error, :invalid_code} = TwoFactor.verify(user, enable_code)
    end

    test "refuses a code from far off", %{user: user, secret: secret} do
      code = NimbleTOTP.verification_code(secret, time: System.os_time(:second) + 120)

      assert {:error, :invalid_code} = TwoFactor.verify(user, code)
    end

    test "accepts each recovery code once and counts what's left", %{user: user, recovery_codes: [code | _]} do
      assert {:ok, {:recovery_code, 9}} = TwoFactor.verify(user, String.upcase(code))
      assert {:error, :invalid_code} = TwoFactor.verify(user, code)
    end

    test "won't take another user's recovery code", %{recovery_codes: [code | _]} do
      other = Fixtures.user_fixture()
      Fixtures.two_factor_fixture(other)

      assert {:error, :invalid_code} = TwoFactor.verify(other, code)
    end

    test "nothing works for a user without it" do
      assert {:error, :invalid_code} = TwoFactor.verify(Fixtures.user_fixture(), "123456")
    end
  end

  describe "disable/2 and regenerate_recovery_codes/2" do
    setup %{user: user}, do: Fixtures.two_factor_fixture(user)

    test "turning it off needs a code", %{user: user, secret: secret} do
      assert {:error, :invalid_code} = TwoFactor.disable(user, "000000")
      assert TwoFactor.enabled?(user)

      assert :ok = TwoFactor.disable(user, Fixtures.next_totp_code(secret))
      refute TwoFactor.enabled?(user)
    end

    test "a recovery code can turn it off", %{user: user, recovery_codes: [code | _]} do
      assert :ok = TwoFactor.disable(user, code)
      refute TwoFactor.enabled?(user)
    end

    test "new recovery codes replace the old ones", %{user: user, secret: secret, recovery_codes: [old | _]} do
      assert {:ok, [new | _] = codes} = TwoFactor.regenerate_recovery_codes(user, Fixtures.next_totp_code(secret))
      assert length(codes) == 10

      assert {:error, :invalid_code} = TwoFactor.verify(user, old)
      assert {:ok, {:recovery_code, 9}} = TwoFactor.verify(user, new)
    end
  end

  describe "organization requirement" do
    setup %{user: user} do
      %{org: Fixtures.org_fixture(user)}
    end

    test "an admin has to have it on to require it", %{user: user, org: org} do
      assert {:error, :two_factor_off} = TwoFactor.set_org_requirement(org, user, true)

      Fixtures.two_factor_fixture(user)

      assert {:ok, %{require_two_factor: true}} = TwoFactor.set_org_requirement(org, user, true)
    end

    test "turning it off needs nothing of the admin", %{user: user, org: org} do
      Fixtures.two_factor_fixture(user)
      {:ok, org} = TwoFactor.set_org_requirement(org, user, true)
      {1, _} = Repo.delete_all(UserTOTP)

      assert {:ok, %{require_two_factor: false}} = TwoFactor.set_org_requirement(org, user, false)
    end

    test "members without it don't meet it", %{user: user, org: org} do
      member = Fixtures.user_fixture()
      {:ok, _} = Accounts.add_org_user(org, member, %{role: :view})
      Fixtures.two_factor_fixture(user)

      assert TwoFactor.meets_org_requirement?(org, member)

      {:ok, org} = TwoFactor.set_org_requirement(org, user, true)

      assert TwoFactor.meets_org_requirement?(org, user)
      refute TwoFactor.meets_org_requirement?(org, member)
      refute TwoFactor.meets_org_requirement?(org.id, member)
      assert [%{id: member_id}] = TwoFactor.members_without(org)
      assert member_id == member.id
      assert [%{id: org_id}] = TwoFactor.orgs_requiring(member)
      assert org_id == org.id
    end
  end

  describe "Accounts.authenticate/2" do
    test "refuses a password alone once two-factor is on", %{user: user} do
      assert {:ok, _} = Accounts.authenticate(user.email, "test_password")

      Fixtures.two_factor_fixture(user)

      assert {:error, :two_factor_required} = Accounts.authenticate(user.email, "test_password")
      assert {:error, :authentication_failed} = Accounts.authenticate(user.email, "wrong")
    end
  end

  test "removing an account removes its authenticator app", %{user: user} do
    Fixtures.two_factor_fixture(user)

    {:ok, _} = Accounts.remove_account(user.id)

    refute Repo.exists?(UserTOTP)
  end
end
