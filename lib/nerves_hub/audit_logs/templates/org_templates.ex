defmodule NervesHub.AuditLogs.OrgTemplates do
  @moduledoc """
  Audit log entries for what belongs to an organization rather than to one of
  its products.
  """
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs
  alias NervesHub.Webhooks.Webhook

  # Webhooks are described by their host rather than their URL. Some receivers
  # (chat incoming webhooks, for one) put their credentials in the URL, and the
  # audit log is readable by everyone in the organization.
  @spec audit_webhook_created(User.t(), Org.t(), Webhook.t()) :: :ok
  def audit_webhook_created(user, org, webhook) do
    description =
      "User #{user.name} added webhook #{webhook.id} sending #{Enum.join(webhook.events, ", ")} from #{products(webhook)} to #{webhook_host(webhook)}"

    AuditLogs.audit!(user, org, description)
  end

  @spec audit_webhook_updated(User.t(), Org.t(), Webhook.t()) :: :ok
  def audit_webhook_updated(user, org, webhook) do
    state = if webhook.enabled, do: "on", else: "off"

    description =
      "User #{user.name} updated webhook #{webhook.id} (#{state}) sending #{Enum.join(webhook.events, ", ")} from #{products(webhook)} to #{webhook_host(webhook)}"

    AuditLogs.audit!(user, org, description)
  end

  @spec audit_webhook_deleted(User.t(), Org.t(), Webhook.t()) :: :ok
  def audit_webhook_deleted(user, org, webhook) do
    description = "User #{user.name} removed webhook #{webhook.id} sending to #{webhook_host(webhook)}"

    AuditLogs.audit!(user, org, description)
  end

  @spec audit_webhook_secret_regenerated(User.t(), Org.t(), Webhook.t()) :: :ok
  def audit_webhook_secret_regenerated(user, org, webhook) do
    description = "User #{user.name} regenerated the signing secret of webhook #{webhook.id}"

    AuditLogs.audit!(user, org, description)
  end

  defp webhook_host(%Webhook{url: url}), do: URI.parse(url).host

  defp products(%Webhook{all_products: true}), do: "every product"

  defp products(%Webhook{products: products}) do
    "#{if length(products) == 1, do: "product", else: "products"} #{Enum.map_join(products, ", ", & &1.name)}"
  end
end
