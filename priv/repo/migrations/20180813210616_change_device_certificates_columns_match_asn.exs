defmodule NervesHubWebCore.Repo.Migrations.ChangeDeviceCertificatesColumnsMatchAsn do
  use Ecto.Migration

  def up do
    rename(table(:device_certificates), :valid_after, to: :not_before)
    rename(table(:device_certificates), :valid_before, to: :not_after)
  end
end
