defmodule NervesHubWeb.FirmwareView do
  use NervesHubWeb, :view

  def format_signed(%{signed: signed}, _tenant) when signed == false do
    "No"
  end

  def format_signed(%{tenant_key_id: tenant_key_id}, tenant) do
    key = Enum.find(tenant.tenant_keys, &(&1.id == tenant_key_id))
    "#{key.name}"
  end
end
