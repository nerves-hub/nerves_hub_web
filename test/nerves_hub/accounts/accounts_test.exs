defmodule NervesHub.AccountsTest do
  use NervesHub.DataCase, async: true

  alias Ecto.Changeset
  alias NervesHub.Accounts
  alias NervesHub.Accounts.Invite
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.User
  alias NervesHub.Accounts.UserToken
  alias NervesHub.Fixtures
  alias NervesHub.Support.Utils
  alias NervesHub.Utils.Base62

  @required_org_params %{name: "Org"}

  setup do
    user = Fixtures.user_fixture()

    {:ok,
     %{
       user: user
     }}
  end

  test "create_org with required params", %{user: user} do
    {:ok, %Org{} = result_org} = Accounts.create_org(user, @required_org_params)

    assert result_org.name == @required_org_params.name
  end

  test "create_org with duplicate name", %{user: user} do
    {:ok, %Org{}} = Accounts.create_org(user, @required_org_params)
    assert {:error, %Changeset{}} = Accounts.create_org(user, @required_org_params)
  end

  test "create_org with invalid characters", %{user: user} do
    assert {:error, %Changeset{}} = Accounts.create_org(user, %{name: "Org with space"})
    assert {:error, %Changeset{}} = Accounts.create_org(user, %{name: "Org with %"})
  end

  test "create_org with user" do
    user = Fixtures.user_fixture()
    {:ok, %Org{} = org1} = Accounts.create_org(user, %{name: "An_Org"})
    assert org1 in Accounts.get_user_orgs(user)
  end

  test "create_org without required params", %{user: user} do
    assert {:error, %Changeset{}} = Accounts.create_org(user, %{})
  end

  test "soft_delete_org" do
    user = Fixtures.user_fixture()
    {:ok, %Org{} = org} = Accounts.create_org(user, %{name: "An_Org"})

    assert {:ok, _org} = Accounts.soft_delete_org(org)
    refute is_nil(Repo.reload(org).deleted_at)
  end

  test "user cannot have two of the same org" do
    params = %{
      name: "Testy Smith  ",
      org_name: "smiths.com",
      email: "testy@smiths.com",
      password: "test_password"
    }

    {:ok, %User{} = user} = Accounts.create_user(params)
    {:ok, %Org{}} = Accounts.create_org(user, %{name: "An_Org"})

    [result_org] = Accounts.get_user_orgs(user)

    assert {:error, %Changeset{}} = Accounts.add_org_user(result_org, user, %{role: :admin})
  end

  test "add user and remove user from an org" do
    user_params = %{
      name: "Testy Smith",
      email: "testy@smiths.com",
      password: "test_password"
    }

    {:ok, %User{} = user} = Accounts.create_user(user_params)
    {:ok, %Org{} = org_1} = Accounts.create_org(user, %{name: "org1"})

    [result_org_1] = Accounts.get_user_orgs(user)

    assert result_org_1.name == org_1.name
    assert user.name == user_params.name

    tmp_user = Fixtures.user_fixture()
    {:ok, %Org{} = org_2} = Accounts.create_org(tmp_user, %{name: "org2"})
    {:ok, _org_user} = Accounts.add_org_user(org_2, user, %{role: :admin})
    user_orgs = Accounts.get_user_orgs(user)

    assert org_1 in user_orgs
    assert org_2 in user_orgs
    assert Enum.count(user_orgs) == 2

    :ok = Accounts.remove_org_user(org_2, user)
    user_orgs = Accounts.get_user_orgs(user)

    assert user_orgs == [org_1]
  end

  test "Unable to remove the last user from an org" do
    user = Fixtures.user_fixture()
    {:ok, org} = Accounts.create_org(user, %{name: "org1"})

    assert {:error, :last_user} = Accounts.remove_org_user(org, user)
  end

  test "find_org_user_with_device : fetch OrgUser for a user and device id", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    user2 = Fixtures.user_fixture()

    assert %OrgUser{} = Accounts.find_org_user_with_device(user, device.id)
    assert nil == Accounts.find_org_user_with_device(user2, device.id)
  end

  test "fetch_firmware_signing_keys/2 returns only the org's keys of the requested scheme", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    fwup_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(fwup_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)
    esp_idf_key = Fixtures.esp_idf_key_fixture(org, user)

    # Another org's keys never belong to this device, whatever their scheme.
    other_org = Fixtures.org_fixture(user, %{name: "other-org"})
    _ = Fixtures.org_key_fixture(other_org, user, tmp_dir)

    assert [%OrgKey{id: id}] = Accounts.fetch_firmware_signing_keys(device.id, :ed25519)
    assert id == fwup_key.id

    assert [%OrgKey{id: id}] = Accounts.fetch_firmware_signing_keys(device.id, :secure_boot_v2_rsa)
    assert id == esp_idf_key.id

    assert [] = Accounts.fetch_firmware_signing_keys(device.id, :x509_certificate)
  end

  describe "authenticate" do
    setup do
      user_params = %{
        orgs: [%{name: "test org 1"}],
        name: "Testy Smith",
        email: "testy@smiths.com",
        password: "test_password"
      }

      {:ok, user} = Accounts.create_user(user_params)

      {:ok, %{user: user}}
    end

    test "with valid credentials", %{user: user} do
      target_email = user.email

      assert {:ok, %User{email: ^target_email}} =
               Accounts.authenticate(user.email, "test_password")
    end

    test "with invalid credentials", %{user: user} do
      assert {:error, :authentication_failed} =
               Accounts.authenticate(user.email, "wrong password")
    end

    test "with blank password", %{user: user} do
      assert {:error, :authentication_failed} =
               Accounts.authenticate(user.email, "")
    end

    test "password is nil", %{user: user} do
      assert {:error, :authentication_failed} =
               Accounts.authenticate(user.email, nil)
    end

    test "with non existent user email" do
      assert {:error, :authentication_failed} =
               Accounts.authenticate("non existent email", "wrong password")
    end
  end

  test "authenticate with an email address with a capital letter" do
    expected_email = "ThatsTesty@smiths.com"

    params = %{
      name: "Testy Smith",
      org_name: "smiths.com",
      email: expected_email,
      password: "test_password"
    }

    {:ok, %User{} = user} = Accounts.create_user(params)

    assert user.email == expected_email

    assert {:ok, %User{email: ^expected_email}} =
             Accounts.authenticate(user.email, "test_password")
  end

  describe "org_key" do
    test "name must be unique", %{user: user} do
      {:ok, org} = Accounts.create_org(user, @required_org_params)

      {:ok, _} =
        Accounts.create_org_key(%{
          name: "org's key",
          org_id: org.id,
          key: "FMBdNKrU3qlyErQtpqxsq50nGAXz03DCeEXPt2iKBe0=",
          created_by_id: user.id
        })

      assert {:error, %Ecto.Changeset{errors: [name: {"has already been taken", [_ | _]}]}} =
               Accounts.create_org_key(%{
                 name: "org's key",
                 org_id: org.id,
                 key: "FMBdNKrU3qlyErQtpqxsq50nGAXz03DCeEXPt2iKBe0=",
                 created_by_id: user.id
               })
    end

    test "key must be unique", %{user: user} do
      {:ok, org} = Accounts.create_org(user, @required_org_params)

      {:ok, _} =
        Accounts.create_org_key(%{
          name: "org's key",
          org_id: org.id,
          key: "FMBdNKrU3qlyErQtpqxsq50nGAXz03DCeEXPt2iKBe0=",
          created_by_id: user.id
        })

      {:error, %Ecto.Changeset{}} =
        Accounts.create_org_key(%{name: "org's second key", org_id: org.id, key: "foo"})
    end

    test "cannot change org_id once created", %{user: user} do
      org = Fixtures.org_fixture(user)
      first_id = org.id
      org_key = Fixtures.org_key_fixture(org, user)

      other_org = Fixtures.org_fixture(user, %{name: "another_org"})

      assert {:ok, %OrgKey{org_id: ^first_id}} =
               Accounts.update_org_key(org_key, %{org_id: other_org.id})
    end

    test "key must be valid", %{user: user} do
      {:ok, org} = Accounts.create_org(user, @required_org_params)

      assert {:error,
              %Ecto.Changeset{errors: [key: {"invalid key, please check this is a valid Ed25519 public key", []}]}} =
               Accounts.create_org_key(%{
                 name: "org's key",
                 org_id: org.id,
                 key: "foobar",
                 created_by_id: user.id
               })
    end
  end

  describe "org_metrics" do
    setup [:setup_org_metric]

    test "create", %{org: org, firmware: firmware} do
      assert {:ok, org_metric} = Accounts.create_org_metric(org.id, DateTime.utc_now())
      assert org_metric.devices == 1
      assert org_metric.bytes_stored == firmware.size
    end
  end

  test "accept invite", %{user: user} do
    org = Fixtures.org_fixture(user)

    {:ok, %Invite{} = invite} =
      Accounts.invite(
        %{"email" => "accepted_invite@test.org", "role" => "view"},
        org,
        user
      )

    assert {:ok, %OrgUser{}} =
             Accounts.create_user_from_invite(invite, org, %{
               "password" => "password123456",
               "name" => "Invited"
             })
  end

  test "accept invite with invalid params", %{user: user} do
    org = Fixtures.org_fixture(user)

    {:ok, %Invite{} = invite} =
      Accounts.invite(
        %{"email" => "failed_accepted_invite@test.org", "role" => "view"},
        org,
        user
      )

    {:error, changeset} = Accounts.create_user_from_invite(invite, org, %{"invalid" => "params"})
    assert "can't be blank" in errors_on(changeset).password
    assert "can't be blank" in errors_on(changeset).name
  end

  describe "org invitations" do
    test "an existing user is invited rather than added", %{user: user} do
      org = Fixtures.org_fixture(user)
      new_user = Fixtures.user_fixture()

      assert {:ok, %Invite{} = invite} =
               Accounts.invite(%{"email" => new_user.email, "role" => "view"}, org, user)

      assert Accounts.get_org_user(org, new_user) == {:error, :not_found}

      assert {:ok, %OrgUser{role: :view}} = Accounts.accept_invite(invite, new_user)
      assert {:ok, %OrgUser{}} = Accounts.get_org_user(org, new_user)

      assert Repo.reload(invite).accepted
    end

    test "an invite can only be accepted by the user it was sent to", %{user: user} do
      org = Fixtures.org_fixture(user)
      someone_else = Fixtures.user_fixture()

      {:ok, invite} =
        Accounts.invite(%{"email" => "invited@test.org", "role" => "view"}, org, user)

      assert Accounts.accept_invite(invite, someone_else) == {:error, :email_mismatch}
      assert Accounts.get_org_user(org, someone_else) == {:error, :not_found}
    end

    test "a declined invite is no longer valid or outstanding", %{user: user} do
      org = Fixtures.org_fixture(user)

      {:ok, invite} =
        Accounts.invite(%{"email" => "declined@test.org", "role" => "view"}, org, user)

      assert {:ok, _} = Accounts.get_valid_invite(invite.token)

      assert {:ok, declined} = Accounts.decline_invite(invite)
      assert declined.declined_at

      assert Accounts.get_valid_invite(invite.token) == {:error, :invite_not_found}
      assert Accounts.get_invites_for_org(org) == []
    end

    test "a member of the org cannot be invited again", %{user: user} do
      org = Fixtures.org_fixture(user)

      {:error, changeset} =
        Accounts.invite(%{"email" => user.email, "role" => "view"}, org, user)

      assert "is already a member of this organization" in errors_on(changeset).email
    end

    test "an invitee with a pending invite cannot be invited again", %{user: user} do
      org = Fixtures.org_fixture(user)

      {:ok, _} = Accounts.invite(%{"email" => "invited@test.org", "role" => "view"}, org, user)

      {:error, changeset} =
        Accounts.invite(%{"email" => "invited@test.org", "role" => "manage"}, org, user)

      assert "has already been invited to this organization" in errors_on(changeset).email
    end

    test "the pending invite check ignores the case of the email", %{user: user} do
      org = Fixtures.org_fixture(user)

      {:ok, _} = Accounts.invite(%{"email" => "Josh@Example.com", "role" => "view"}, org, user)

      {:error, changeset} =
        Accounts.invite(%{"email" => "josh@example.com", "role" => "view"}, org, user)

      assert "has already been invited to this organization" in errors_on(changeset).email
      assert length(Accounts.get_invites_for_org(org)) == 1
    end

    test "rescinding and resending tell an accepted invite from a declined one", %{user: user} do
      org = Fixtures.org_fixture(user)

      {:ok, accepted} = Accounts.invite(%{"email" => "accepted@test.org", "role" => "view"}, org, user)
      {:ok, declined} = Accounts.invite(%{"email" => "declined@test.org", "role" => "view"}, org, user)

      invitee = Fixtures.user_fixture(%{email: "accepted@test.org"})
      {:ok, _org_user} = Accounts.accept_invite(accepted, invitee)
      {:ok, _} = Accounts.decline_invite(declined)

      assert Accounts.delete_invite(org, accepted.token) == {:error, :accepted}
      assert Accounts.delete_invite(org, declined.token) == {:error, :declined}
      assert Accounts.delete_invite(org, Ecto.UUID.generate()) == {:error, :not_found}

      assert Accounts.resend_invite(org, accepted.token) == {:error, :accepted}
      assert Accounts.resend_invite(org, declined.token) == {:error, :declined}
      assert Accounts.resend_invite(org, Ecto.UUID.generate()) == {:error, :not_found}
    end

    test "an invitee can be re-invited once a previous invite was declined", %{user: user} do
      org = Fixtures.org_fixture(user)

      {:ok, invite} =
        Accounts.invite(%{"email" => "invited@test.org", "role" => "view"}, org, user)

      {:ok, _} = Accounts.decline_invite(invite)

      assert {:ok, %Invite{}} =
               Accounts.invite(%{"email" => "invited@test.org", "role" => "view"}, org, user)
    end
  end

  test "can create a valid base 62 encoded user token", %{user: user} do
    assert <<"nhu_", token::binary>> =
             Accounts.create_user_api_token(user, "Test token")

    assert {:ok, <<_token::32-bytes, _crc::32>>} = Base62.decode(token)
  end

  test "old tokens are allowed", %{user: %{id: id} = user} do
    user_token = Utils.create_v1_user_token!(user)
    {:ok, query} = UserToken.verify_api_token_query(user_token.old_token)
    assert {%{id: ^id}, _user_token} = Repo.one!(query)
  end

  describe "create_user_session_token/1" do
    test "it creates a session token for the user", %{user: user} do
      token = Accounts.create_user_session_token(user)
      user_by_token = Accounts.get_user_by_session_token(token)
      assert user.id == user_by_token.id

      {:ok, user_token} = Accounts.get_user_token(token)
      assert user_token.context == "session"
      assert user_token.token
    end

    test "it sets a note on the user_token", %{user: user} do
      token = Accounts.create_user_session_token(user, "A nice note")
      {:ok, user_token} = Accounts.get_user_token(token)
      assert user_token.note == "A nice note"
    end
  end

  describe "UserToken CRCs" do
    test "if the crc doesn't match, return :crc_mismatch", %{user: user} do
      token = Accounts.create_user_api_token(user, "Test token")

      <<"nh", _u, "_", token_with_crc::binary>> = token

      {:ok, <<token::32-bytes, crc::32>>} = Base62.decode(token_with_crc)

      encoded_token = Base62.encode(<<token::32-bytes, crc + 1::32>>)

      assert {:error, :crc_mismatch} = UserToken.verify_api_token_query("nhu_#{encoded_token}")
    end

    test "rejects unsupported token prefix", %{user: user} do
      token = Accounts.create_user_api_token(user, "Test token")

      <<"nhu_", only_token::binary>> = token

      assert {:error, :invalid_token} = UserToken.verify_api_token_query(only_token)
    end

    test "rejects non-base62 characters", %{user: user} do
      token = Accounts.create_user_api_token(user, "Test token")

      partial = String.slice(token, 0, byte_size(token) - 1)

      assert {:error, :invalid_token} = UserToken.verify_api_token_query("#{partial}.")
    end
  end

  def setup_org_metric(%{user: user, tmp_dir: tmp_dir}) do
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)
    _ = create_firmware_transfer(org, firmware)

    [org: org, product: product, org_key: org_key, firmware: firmware, device: device]
  end

  def create_firmware_transfer(org, firmware) do
    {:ok, firmware_transfer} =
      NervesHub.Firmwares.create_firmware_transfer(%{
        org_id: org.id,
        firmware_uuid: firmware.uuid,
        bytes_sent: firmware.size,
        bytes_total: firmware.size,
        remote_ip: "127.0.0.1",
        timestamp: DateTime.utc_now()
      })

    firmware_transfer
  end
end
