defmodule NervesHub.Ash.Devices.CACertificateTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Ash.Devices.CACertificate
  alias NervesHub.Fixtures

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    %{db_cert: db_cert} = Fixtures.ca_certificate_fixture(org)

    %{org: org, db_cert: db_cert}
  end

  describe "read" do
    test "list_by_org returns ca certs", %{org: org, db_cert: db_cert} do
      certs = CACertificate.list_by_org!(org.id)
      assert Enum.any?(certs, &(&1.id == db_cert.id))
    end

    test "get_by_org_and_serial returns cert", %{org: org, db_cert: db_cert} do
      found = CACertificate.get_by_org_and_serial!(org.id, db_cert.serial)
      assert found.id == db_cert.id
    end

    test "get_by_serial returns cert", %{db_cert: db_cert} do
      found = CACertificate.get_by_serial!(db_cert.serial)
      assert found.id == db_cert.id
    end
  end

  describe "get_by_aki" do
    test "returns cert by AKI", %{db_cert: db_cert} do
      found = CACertificate.get_by_aki!(db_cert.aki)
      assert found.id == db_cert.id
    end
  end

  describe "get_by_ski" do
    test "returns cert by SKI", %{db_cert: db_cert} do
      found = CACertificate.get_by_ski!(db_cert.ski)
      assert found.id == db_cert.id
    end
  end

  describe "known_ski" do
    test "returns true for known SKI", %{db_cert: db_cert} do
      assert CACertificate.known_ski!(db_cert.ski) == true
    end

    test "returns false for unknown SKI" do
      assert CACertificate.known_ski!("nonexistent") == false
    end
  end

  describe "update" do
    test "updates description", %{db_cert: db_cert} do
      ash_cert = CACertificate.get!(db_cert.id)
      updated = CACertificate.update!(ash_cert, %{description: "Updated CA"})
      assert updated.description == "Updated CA"
    end
  end

  describe "destroy" do
    test "deletes CA certificate", %{db_cert: db_cert} do
      ash_cert = CACertificate.get!(db_cert.id)
      assert :ok = CACertificate.destroy!(ash_cert)
    end
  end
end
