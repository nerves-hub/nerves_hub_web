defmodule NervesHubWeb.ArchiveView do
  use NervesHubWeb, :view

  def format_signed(%{org_key_id: org_key_id}, org) do
    key = Enum.find(org.org_keys, &(&1.id == org_key_id))
    "#{key.name}"
  end
end
