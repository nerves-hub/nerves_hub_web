defmodule NervesHub.AuditLogs.ProductTemplates do
  @moduledoc """
  Audit log entries for what belongs to a product rather than to one of its
  devices or deployment groups.

  Each description is a `NervesHub.AuditLogs.Template`. Names a user typed
  (a script's, an API key's, a custom role's) and an error's reason, which a
  device sent, go in as values.
  """
  alias NervesHub.Accounts.OrgRole
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.Template
  alias NervesHub.ErrorReports.ErrorGroup
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Products.ApiKey
  alias NervesHub.Products.Product
  alias NervesHub.Scripts.Script

  @spec audit_script_created(AuditLogs.actor(), Product.t(), Script.t()) :: :ok
  def audit_script_created(actor, product, script) do
    template =
      Template.new("%{actor} created script named %{script} with id %{script_id} for product %{resource}",
        script: script.name,
        script_id: script.id
      )

    AuditLogs.audit!(actor, product, template)
  end

  @spec audit_script_updated(AuditLogs.actor(), Product.t(), Script.t()) :: :ok
  def audit_script_updated(actor, product, script) do
    template =
      Template.new("%{actor} updated script named %{script} with id %{script_id} for product %{resource}",
        script: script.name,
        script_id: script.id
      )

    AuditLogs.audit!(actor, product, template)
  end

  @spec audit_script_deleted(AuditLogs.actor(), Product.t(), Script.t()) :: :ok
  def audit_script_deleted(actor, product, script) do
    template = Template.new("%{actor} removed script named %{script} from product %{resource}", script: script.name)

    AuditLogs.audit!(actor, product, template)
  end

  @spec audit_firmware_deleted(AuditLogs.actor(), Product.t(), Firmware.t()) :: :ok
  def audit_firmware_deleted(actor, product, firmware) do
    template =
      Template.new("%{actor} deleted firmware %{version} (%{firmware}) from product %{resource}",
        version: firmware.version,
        firmware: firmware
      )

    AuditLogs.audit!(actor, product, template)
  end

  @spec audit_api_key_created(User.t(), Product.t(), ApiKey.t()) :: :ok
  def audit_api_key_created(user, product, api_key) do
    template =
      Template.new("%{actor} created API key %{key} with the %{role} role for product %{resource}",
        key: api_key.name,
        role: role_name(api_key)
      )

    AuditLogs.audit!(user, product, template)
  end

  @spec audit_api_key_deactivated(User.t(), Product.t(), ApiKey.t()) :: :ok
  def audit_api_key_deactivated(user, product, api_key) do
    template = Template.new("%{actor} deactivated API key %{key} for product %{resource}", key: api_key.name)

    AuditLogs.audit!(user, product, template)
  end

  defp role_name(api_key) do
    case ApiKey.assigned_role(api_key) do
      %OrgRole{name: name} -> "#{name} custom"
      role -> to_string(role)
    end
  end

  @spec audit_error_group_resolved(AuditLogs.actor(), Product.t(), ErrorGroup.t()) :: :ok
  def audit_error_group_resolved(actor, product, group) do
    error_group(actor, product, group, "%{actor} marked error %{error} (%{reason}) as resolved for product %{resource}")
  end

  @spec audit_error_group_muted(AuditLogs.actor(), Product.t(), ErrorGroup.t()) :: :ok
  def audit_error_group_muted(actor, product, group) do
    error_group(actor, product, group, "%{actor} muted error %{error} (%{reason}) for product %{resource}")
  end

  @spec audit_error_group_reopened(AuditLogs.actor(), Product.t(), ErrorGroup.t()) :: :ok
  def audit_error_group_reopened(actor, product, group) do
    error_group(actor, product, group, "%{actor} reopened error %{error} (%{reason}) for product %{resource}")
  end

  defp error_group(actor, product, group, text) do
    AuditLogs.audit!(actor, product, Template.new(text, error: group.id, reason: group.reason))
  end

  @spec audit_extension_set_for_devices(AuditLogs.actor(), Product.t(), String.t(), boolean(), non_neg_integer()) :: :ok
  def audit_extension_set_for_devices(actor, product, extension, enabled, count) do
    template =
      Template.new(
        "%{actor} #{(enabled && "enabled") || "disabled"} the %{extension} extension on %{count} device(s) in product %{resource}",
        extension: extension,
        count: count
      )

    AuditLogs.audit!(actor, product, template)
  end
end
