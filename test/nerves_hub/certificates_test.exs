defmodule NervesHub.CertificatesTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.{Certificate, Fixtures}

  setup_all do
    cert =
      Path.join([Fixtures.path(), "ssl", "user.pem"])
      |> File.read!()
      |> X509.Certificate.from_pem!()

    %{cert: cert}
  end

  test "authority key id", %{cert: cert} do
    assert <<99, 249, 44, 251, 191, 143, 83, 203, 11, 228, 56, 74, 158, 97, 218, 5, 252, 14, 122,
             149>> == Certificate.get_aki(cert)
  end

  test "subject key id", %{cert: cert} do
    assert <<203, 128, 98, 85, 212, 151, 213, 148, 10, 243, 186, 110, 20, 35, 75, 216, 144, 15,
             181, 20>> == Certificate.get_ski(cert)
  end

  test "common name", %{cert: cert} do
    assert "NervesHub User Certificate" == Certificate.get_common_name(cert)
  end

  test "serial number", %{cert: cert} do
    assert "158098897653878678601091983566405937658689714637" ==
             Certificate.get_serial_number(cert)
  end

  test "validity", %{cert: cert} do
    {not_before, not_after} = Certificate.get_validity(cert)

    assert not_before.year == 2018
    assert not_before.month == 7
    assert not_before.day == 27
    assert not_after.year == 2019
    assert not_after.month == 7
    assert not_after.day == 27
  end
end
