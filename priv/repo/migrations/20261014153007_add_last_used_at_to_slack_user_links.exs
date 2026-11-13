defmodule NervesHub.Repo.Migrations.AddLastUsedAtToSlackUserLinks do
  use Ecto.Migration

  def change() do
    # When Slack last acted through the link, shown in Account Settings so a
    # link nobody recognises stands out.
    alter table(:slack_user_links) do
      add(:last_used_at, :utc_datetime_usec)
    end
  end
end
