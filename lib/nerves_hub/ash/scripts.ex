defmodule NervesHub.Ash.Scripts do
  use Ash.Domain,
    extensions: [AshJsonApi.Domain, AshGraphql.Domain]

  resources do
    resource NervesHub.Ash.Scripts.Script
  end
end
