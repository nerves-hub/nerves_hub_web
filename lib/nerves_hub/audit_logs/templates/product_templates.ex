defmodule NervesHub.AuditLogs.ProductTemplates do
  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.AuditLog
  alias NervesHub.Accounts.User
  alias NervesHub.Products.Product
  alias NervesHub.Scripts.Script

  @spec audit_script_created(User.t(), Product.t(), Script.t()) :: AuditLog.t()
  def audit_script_created(user, product, script) do
    description =
      "User #{user.name} created script named #{script.name} with id #{script.id} for product #{product.name}"

    AuditLogs.audit!(user, product, description)
  end

  @spec audit_script_created(User.t(), Product.t(), Script.t()) :: AuditLog.t()
  def audit_script_updated(user, product, script) do
    description =
      "User #{user.name} updated script named #{script.name} with id #{script.id} for product #{product.name}"

    AuditLogs.audit!(user, product, description)
  end

  @spec audit_script_deleted(User.t(), Product.t(), Script.t()) :: AuditLog.t()
  def audit_script_deleted(user, product, script) do
    description =
      "User #{user.name} removed script named #{script.name} from product #{product.name}"

    AuditLogs.audit!(user, product, description)
  end
end
