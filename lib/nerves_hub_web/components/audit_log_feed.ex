defmodule NervesHubWeb.Components.AuditLogFeed do
  use NervesHubWeb, :component

  import NervesHubWeb.LayoutView, only: [pagination_links: 1]

  alias NervesHubWeb.LayoutView.DateTimeFormat

  attr(:audit_logs, :list)
  attr(:audit_pager, :map)

  def render(assigns) do
    ~H"""
    <div id="audit-log-feed">
      <%= if Enum.empty?(@audit_logs) do %>
        <div class="audit-log-item">
          <p class="text-muted">No activity</p>
        </div>
      <% else %>
        <div :for={audit_log <- @audit_logs} class="audit-log-item" id={audit_log.id}>
          <div class="audit-action-icon icon-update"></div>
          <div>
            <p class="audit-description">{audit_log.description}</p>
            <div class="help-text">
              {DateTimeFormat.from_now(audit_log.inserted_at)}<small> at <%= audit_log.inserted_at %></small>
              {if audit_log.reference_id, do: "(Ref: #{audit_log.reference_id})"}
            </div>
          </div>
        </div>
        {pagination_links(@audit_pager)}
      <% end %>
    </div>
    """
  end
end
