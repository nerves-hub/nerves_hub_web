defmodule NervesHub.AccountsTest do
  use NervesHub.DataCase, async: true

  alias Ecto.Changeset

  alias NervesHub.Accounts
  alias NervesHub.Accounts.{Org, OrgKey, OrgUser, User, Invite}
  alias NervesHub.Fixtures

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
      name: "Testy McTesterson",
      org_name: "mctesterson.com",
      email: "testy@mctesterson.com",
      password: "test_password"
    }

    {:ok, %User{} = user} = Accounts.create_user(params)
    {:ok, %Org{}} = Accounts.create_org(user, %{name: "An_Org"})

    [result_org] = Accounts.get_user_orgs(user)

    assert {:error, %Changeset{}} = Accounts.add_org_user(result_org, user, %{role: :admin})
  end

  test "add user and remove user from an org" do
    user_params = %{
      name: "Testy McTesterson",
      email: "testy@mctesterson.com",
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

  test "find_org_user_with_device : fetch OrgUser for a user and device id" do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    device = Fixtures.device_fixture(org, product, firmware)

    user2 = Fixtures.user_fixture()

    assert %OrgUser{} = Accounts.find_org_user_with_device(user, device.id)
    assert nil == Accounts.find_org_user_with_device(user2, device.id)
  end

  describe "authenticate" do
    setup do
      user_params = %{
        orgs: [%{name: "test org 1"}],
        name: "Testy McTesterson",
        email: "testy@mctesterson.com",
        password: "test_password"
      }

      {:ok, user} = Accounts.create_user(user_params)

      {:ok, %{user: user}}
    end

    test "with valid credentials", %{user: user} do
      target_email = user.email

      assert {:ok, %User{email: ^target_email}} =
               Accounts.authenticate(user.email, user.password)
    end

    test "with invalid credentials", %{user: user} do
      assert {:error, :authentication_failed} =
               Accounts.authenticate(user.email, "wrong password")
    end

    test "with non existent user email" do
      assert {:error, :authentication_failed} =
               Accounts.authenticate("non existent email", "wrong password")
    end
  end

  test "authenticate with an email address with a capital letter" do
    expected_email = "ThatsTesty@mctesterson.com"

    params = %{
      name: "Testy McTesterson",
      org_name: "mctesterson.com",
      email: expected_email,
      password: "test_password"
    }

    {:ok, %User{} = user} = Accounts.create_user(params)

    assert user.email == expected_email

    assert {:ok, %User{email: ^expected_email}} =
             Accounts.authenticate(user.email, user.password)
  end

  test "org_key name must be unique", %{user: user} do
    {:ok, org} = Accounts.create_org(user, @required_org_params)

    {:ok, _} =
      Accounts.create_org_key(%{
        name: "org's key",
        org_id: org.id,
        key: "foo",
        created_by_id: user.id
      })

    assert {:error, %Ecto.Changeset{errors: [name: {"has already been taken", [_ | _]}]}} =
             Accounts.create_org_key(%{
               name: "org's key",
               org_id: org.id,
               key: "foobar",
               created_by_id: user.id
             })
  end

  test "org_key key must be unique", %{user: user} do
    {:ok, org} = Accounts.create_org(user, @required_org_params)

    {:ok, _} =
      Accounts.create_org_key(%{
        name: "org's key",
        org_id: org.id,
        key: "foo",
        created_by_id: user.id
      })

    {:error, %Ecto.Changeset{}} =
      Accounts.create_org_key(%{name: "org's second key", org_id: org.id, key: "foo"})
  end

  test "cannot change org_id of a org_key once created", %{user: user} do
    org = Fixtures.org_fixture(user)
    first_id = org.id
    org_key = Fixtures.org_key_fixture(org, user)

    other_org = Fixtures.org_fixture(user, %{name: "another_org"})

    assert {:ok, %OrgKey{org_id: ^first_id}} =
             Accounts.update_org_key(org_key, %{org_id: other_org.id})
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
      Accounts.add_or_invite_to_org(
        %{"email" => "accepted_invite@test.org", "role" => "view"},
        org,
        user
      )

    assert {:ok, %OrgUser{}} =
             Accounts.create_user_from_invite(invite, org, %{
               "password" => "password123",
               "name" => "Invited"
             })
  end

  test "accept invite with invalid params", %{user: user} do
    org = Fixtures.org_fixture(user)

    {:ok, %Invite{} = invite} =
      Accounts.add_or_invite_to_org(
        %{"email" => "failed_accepted_invite@test.org", "role" => "view"},
        org,
        user
      )

    {:error, changeset} = Accounts.create_user_from_invite(invite, org, %{"invalid" => "params"})
    assert "can't be blank" in errors_on(changeset).password
    assert "can't be blank" in errors_on(changeset).name
  end

  test "invite existing user", %{user: user} do
    org = Fixtures.org_fixture(user)
    new_user = Fixtures.user_fixture()

    assert {:ok, %OrgUser{}} =
             Accounts.add_or_invite_to_org(
               %{"email" => new_user.email, "role" => "view"},
               org,
               user
             )

    {:error, changeset} =
      Accounts.add_or_invite_to_org(%{"email" => new_user.email, "role" => "view"}, org, user)

    assert "is already member" in errors_on(changeset).org_users
  end

  test "can create a user token", %{user: user} do
    assert {:ok, %{token: <<"nhu_", token::binary>>}} =
             Accounts.create_user_token(user, "Test token")

    assert byte_size(token) == 36
  end

  def setup_org_metric(%{user: user}) do
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
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
