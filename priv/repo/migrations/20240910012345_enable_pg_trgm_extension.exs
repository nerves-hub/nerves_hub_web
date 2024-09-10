defmodule NervesHub.Repo.Migrations.EnablePgTrgmExtension do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION pg_trgm", "DROP EXTENSION pg_trgm"
    execute(&add_function/0, &drop_function/0)
  end

  defp add_function do
    repo().query!("""
      create function string_array_to_string(text[], text, text) returns text as $$
         select array_to_string($1, $2, $3)
      $$ language sql cost 1 immutable;
    """, [], [log: :info])
  end

  defp drop_function do
    repo().query!("drop function string_array_to_string(text[], text, text);", [], [log: :info])
  end
end
