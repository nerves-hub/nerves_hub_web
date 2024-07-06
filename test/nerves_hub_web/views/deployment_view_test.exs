defmodule NervesHubWeb.DeploymentViewTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Fixtures
  alias NervesHubWeb.DeploymentView

  describe "edit deployment view" do
    test "sorts firmware dropdown by version" do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0"})
      firmware2 = Fixtures.firmware_fixture(org_key, product, %{version: "1.10.0"})
      firmware3 = Fixtures.firmware_fixture(org_key, product, %{version: "1.8.6"})
      firmware4 = Fixtures.firmware_fixture(org_key, product, %{version: "1.7.0"})
      firmware5 = Fixtures.firmware_fixture(org_key, product, %{version: "1.12.0"})
      firmware6 = Fixtures.firmware_fixture(org_key, product, %{version: "--"})

      unsorted_firmwares = [firmware4, firmware6, firmware2, firmware5, firmware3, firmware]
      sorted_firmwares = DeploymentView.firmware_dropdown_options(unsorted_firmwares)
      sorted_firmware_versions = firmware_versions(sorted_firmwares)

      assert(sorted_firmware_versions == ["2.0.0", "1.12.0", "1.10.0", "1.8.6", "1.7.0", "--"])
    end
  end

  defp firmware_versions(firmware_dropdown_options) do
    firmware_dropdown_options
    |> Enum.map(fn [_, key: display_name] ->
      [version_number | _rest] = String.split(display_name)
      version_number
    end)
  end
end
