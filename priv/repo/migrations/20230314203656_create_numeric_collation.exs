defmodule NervesHub.Repo.Migrations.CreateNumericCollation do
  use Ecto.Migration

  def change do
    execute "create collation if not exists numeric (provider = icu, locale = 'en-u-kn-true');", "drop collation numeric;"
  end
end
