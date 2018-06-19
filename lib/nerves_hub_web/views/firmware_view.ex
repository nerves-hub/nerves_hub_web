defmodule NervesHubWeb.FirmwareView do
  use NervesHubWeb, :view

  def format_timestamp(timestamp) do
    date = timestamp |> Timex.format!("{ISOdate}")
    time = timestamp |> Timex.format!("{h24}:{m}")
    "#{date} #{time}"
  end

  def format_key(%{tenant_key_id: tenant_key_id}, tenant) do
    key = Enum.find(tenant.tenant_keys, &(&1.id == tenant_key_id))
    "#{key.name}"
  end
end
