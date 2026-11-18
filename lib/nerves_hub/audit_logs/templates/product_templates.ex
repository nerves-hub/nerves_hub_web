defmodule NervesHub.AuditLogs.ProductTemplates do
  alias NervesHub.Accounts.OrgRole
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs
  alias NervesHub.ErrorReports.ErrorGroup
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Products.ApiKey
  alias NervesHub.Products.Product
  alias NervesHub.Scripts.Script

  @spec audit_script_created(AuditLogs.actor(), Product.t(), Script.t()) :: :ok
  def audit_script_created(actor, product, script) do
    description =
      "#{AuditLogs.actor_name(actor)} created script named #{script.name} with id #{script.id} for product #{product.name}"

    AuditLogs.audit!(actor, product, description)
  end

  @spec audit_script_updated(AuditLogs.actor(), Product.t(), Script.t()) :: :ok
  def audit_script_updated(actor, product, script) do
    description =
      "#{AuditLogs.actor_name(actor)} updated script named #{script.name} with id #{script.id} for product #{product.name}"

    AuditLogs.audit!(actor, product, description)
  end

  @spec audit_script_deleted(AuditLogs.actor(), Product.t(), Script.t()) :: :ok
  def audit_script_deleted(actor, product, script) do
    description =
      "#{AuditLogs.actor_name(actor)} removed script named #{script.name} from product #{product.name}"

    AuditLogs.audit!(actor, product, description)
  end

  @spec audit_firmware_deleted(AuditLogs.actor(), Product.t(), Firmware.t()) :: :ok
  def audit_firmware_deleted(actor, product, firmware) do
    description =
      "#{AuditLogs.actor_name(actor)} deleted firmware #{firmware.version} (#{firmware.uuid}) from product #{product.name}"

    AuditLogs.audit!(actor, product, description)
  end

  @spec audit_api_key_created(User.t(), Product.t(), ApiKey.t()) :: :ok
  def audit_api_key_created(user, product, api_key) do
    description =
      "User #{user.name} created API key #{api_key.name} with the #{role_name(api_key)} role for product #{product.name}"

    AuditLogs.audit!(user, product, description)
  end

  @spec audit_api_key_deactivated(User.t(), Product.t(), ApiKey.t()) :: :ok
  def audit_api_key_deactivated(user, product, api_key) do
    description = "User #{user.name} deactivated API key #{api_key.name} for product #{product.name}"

    AuditLogs.audit!(user, product, description)
  end

  # A custom role deleted since the key was made leaves the key granting
  # nothing, which is worth saying plainly in the log.
  defp role_name(api_key) do
    case ApiKey.assigned_role(api_key) do
      nil -> "deleted custom"
      %OrgRole{name: name} -> "#{name} custom"
      role -> to_string(role)
    end
  end

  @spec audit_error_group_resolved(AuditLogs.actor(), Product.t(), ErrorGroup.t()) :: :ok
  def audit_error_group_resolved(actor, product, group) do
    description =
      "#{AuditLogs.actor_name(actor)} marked error #{group.id} (#{group.reason}) as resolved for product #{product.name}"

    AuditLogs.audit!(actor, product, description)
  end

  @spec audit_error_group_muted(AuditLogs.actor(), Product.t(), ErrorGroup.t()) :: :ok
  def audit_error_group_muted(actor, product, group) do
    description =
      "#{AuditLogs.actor_name(actor)} muted error #{group.id} (#{group.reason}) for product #{product.name}"

    AuditLogs.audit!(actor, product, description)
  end

  @spec audit_extension_set_for_devices(AuditLogs.actor(), Product.t(), String.t(), boolean(), non_neg_integer()) :: :ok
  def audit_extension_set_for_devices(actor, product, extension, enabled, count) do
    description =
      "#{AuditLogs.actor_name(actor)} #{(enabled && "enabled") || "disabled"} the #{extension} extension on #{count} device(s) in product #{product.name}"

    AuditLogs.audit!(actor, product, description)
  end

  @spec audit_error_group_reopened(AuditLogs.actor(), Product.t(), ErrorGroup.t()) :: :ok
  def audit_error_group_reopened(actor, product, group) do
    description =
      "#{AuditLogs.actor_name(actor)} reopened error #{group.id} (#{group.reason}) for product #{product.name}"

    AuditLogs.audit!(actor, product, description)
  end
end
