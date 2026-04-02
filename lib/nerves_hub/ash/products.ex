defmodule NervesHub.Ash.Products do
  use Ash.Domain,
    extensions: [AshJsonApi.Domain, AshGraphql.Domain]

  resources do
    resource NervesHub.Ash.Products.Product
    resource NervesHub.Ash.Products.Notification
    resource NervesHub.Ash.Products.SharedSecretAuth
  end
end
