defmodule NervesHubWWWWeb.AuditLogView do
  use NervesHubWWWWeb, :view

  alias NervesHubWWWWeb.LayoutView.DateTimeFormat, as: DateTimeFormat
  import NervesHubWWWWeb.LayoutView, only: [pagination_links: 2]

  def actor_link(%{actor_id: id, actor_type: type}, current_id) do
    link_to_resource(type, id, current_id, "audit-log-actor")
  end

  def resource_link(%{resource_id: id, resource_type: type}, current_id) do
    link_to_resource(type, id, current_id, "audit-log-resource")
  end

  defp feed_type(type) do
    to_string(type)
    |> String.downcase()
    |> String.split(".")
    |> Enum.at(-1)
  end

  defp link_to_resource(type, id, current_id, class) do
    simple_type = feed_type(type)

    if id == current_id do
      # no need to link to yourself
      simple_type
    else
      link("#{simple_type} [#{id}]", to: path_for(simple_type, id), class: class)
    end
  end

  def path_for("deployment", _id) do
    # TODO: handle lookup product id
    "/products"
  end

  def path_for("device", _id) do
    # TODO: handle product id lookup
    "/products"
  end

  def path_for("firmware", _id) do
    # TODO: handle product id lookup
    "/products"
  end

  def path_for("user", _id) do
    # TODO: Add route for user#show instead of settings
    ""
  end

  def path_for(simple_type, id) do
    apply(Routes, :"#{simple_type}_path", [Endpoint, :show, id])
  end
end
