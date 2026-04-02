defmodule NervesHub.Ash.AuditLogs do
  use Ash.Domain,
    extensions: [AshJsonApi.Domain, AshGraphql.Domain]

  resources do
    resource NervesHub.Ash.AuditLogs.AuditLog
  end
end
