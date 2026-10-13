defmodule NervesHub.AuditLogs.ProductTemplates do
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs
  alias NervesHub.ErrorReports.ErrorGroup
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Products.Product
  alias NervesHub.Scripts.Script
  alias NervesHub.Webhooks.Webhook

  @spec audit_script_created(User.t(), Product.t(), Script.t()) :: :ok
  def audit_script_created(user, product, script) do
    description =
      "User #{user.name} created script named #{script.name} with id #{script.id} for product #{product.name}"

    AuditLogs.audit!(user, product, description)
  end

  @spec audit_script_created(User.t(), Product.t(), Script.t()) :: :ok
  def audit_script_updated(user, product, script) do
    description =
      "User #{user.name} updated script named #{script.name} with id #{script.id} for product #{product.name}"

    AuditLogs.audit!(user, product, description)
  end

  @spec audit_script_deleted(User.t(), Product.t(), Script.t()) :: :ok
  def audit_script_deleted(user, product, script) do
    description =
      "User #{user.name} removed script named #{script.name} from product #{product.name}"

    AuditLogs.audit!(user, product, description)
  end

  @spec audit_firmware_deleted(User.t(), Product.t(), Firmware.t()) :: :ok
  def audit_firmware_deleted(user, product, firmware) do
    description =
      "User #{user.name} deleted firmware #{firmware.version} (#{firmware.uuid}) from product #{product.name}"

    AuditLogs.audit!(user, product, description)
  end

  @spec audit_error_group_resolved(User.t(), Product.t(), ErrorGroup.t()) :: :ok
  def audit_error_group_resolved(user, product, group) do
    description =
      "User #{user.name} marked error #{group.id} (#{group.reason}) as resolved for product #{product.name}"

    AuditLogs.audit!(user, product, description)
  end

  @spec audit_error_group_muted(User.t(), Product.t(), ErrorGroup.t()) :: :ok
  def audit_error_group_muted(user, product, group) do
    description =
      "User #{user.name} muted error #{group.id} (#{group.reason}) for product #{product.name}"

    AuditLogs.audit!(user, product, description)
  end

  @spec audit_error_group_reopened(User.t(), Product.t(), ErrorGroup.t()) :: :ok
  def audit_error_group_reopened(user, product, group) do
    description =
      "User #{user.name} reopened error #{group.id} (#{group.reason}) for product #{product.name}"

    AuditLogs.audit!(user, product, description)
  end

  # Webhooks are described by their host rather than their URL. Some receivers
  # (chat incoming webhooks, for one) put their credentials in the URL, and the
  # audit log is readable by everyone in the organization.
  @spec audit_webhook_created(User.t(), Product.t(), Webhook.t()) :: :ok
  def audit_webhook_created(user, product, webhook) do
    description =
      "User #{user.name} added webhook #{webhook.id} sending #{Enum.join(webhook.events, ", ")} to #{webhook_host(webhook)} for product #{product.name}"

    AuditLogs.audit!(user, product, description)
  end

  @spec audit_webhook_updated(User.t(), Product.t(), Webhook.t()) :: :ok
  def audit_webhook_updated(user, product, webhook) do
    state = if webhook.enabled, do: "on", else: "off"

    description =
      "User #{user.name} updated webhook #{webhook.id} (#{state}) sending #{Enum.join(webhook.events, ", ")} to #{webhook_host(webhook)} for product #{product.name}"

    AuditLogs.audit!(user, product, description)
  end

  @spec audit_webhook_deleted(User.t(), Product.t(), Webhook.t()) :: :ok
  def audit_webhook_deleted(user, product, webhook) do
    description =
      "User #{user.name} removed webhook #{webhook.id} sending to #{webhook_host(webhook)} from product #{product.name}"

    AuditLogs.audit!(user, product, description)
  end

  @spec audit_webhook_secret_regenerated(User.t(), Product.t(), Webhook.t()) :: :ok
  def audit_webhook_secret_regenerated(user, product, webhook) do
    description =
      "User #{user.name} regenerated the signing secret of webhook #{webhook.id} for product #{product.name}"

    AuditLogs.audit!(user, product, description)
  end

  defp webhook_host(%Webhook{url: url}), do: URI.parse(url).host
end
