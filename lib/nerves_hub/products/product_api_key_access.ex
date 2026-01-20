defmodule NervesHub.Products.ProductAPIKeyAccess do
  alias NervesHub.Accounts.Org
  alias NervesHub.Products.Product
  alias NervesHub.Devices

  def access_device?(%Product{org: %Org{} = org}, device_identifier) do
    case Devices.get_device_by_identifier(org, device_identifier) do
      {:ok, _} -> true
      _ -> false
    end
  end
end
