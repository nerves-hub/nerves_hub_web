defmodule NervesHub.AuditLogs.ProductTemplates do
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs
  alias NervesHub.ErrorReports.ErrorGroup
  alias NervesHub.Products.Product
  alias NervesHub.Scripts.Script

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
end
