defmodule NervesHub.Ash.Archives do
  use Ash.Domain,
    extensions: [AshJsonApi.Domain, AshGraphql.Domain]

  resources do
    resource NervesHub.Ash.Archives.Archive
  end
end
