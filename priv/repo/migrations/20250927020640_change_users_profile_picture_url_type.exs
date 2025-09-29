defmodule NervesHub.Repo.Migrations.ChangeUsersProfilePictureUrlType do
  use Ecto.Migration

  def change() do
    alter table("users") do
      modify(:profile_picture_url, :text, from: :string)
    end
  end
end
