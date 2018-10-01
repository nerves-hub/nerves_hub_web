# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     NervesHubCore.Repo.insert!(%NervesHubWWW.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# The seeds are run on every deploy. Therefore, it is important
# that first check to see if the data you are trying to insert
# has been run yet.
alias NervesHubCore.{Accounts, Accounts.User, Repo, Firmwares}

defmodule NervesHubCore.SeedHelpers do
  alias NervesHubCore.Fixtures

  def seed_product(product_name, org) do
    product = Fixtures.product_fixture(org, %{name: product_name})

    firmware_versions = ["0.1.0", "0.1.1", "0.1.2", "1.0.0"]

    org_with_keys_and_users =
      org |> NervesHubCore.Accounts.Org.with_org_keys() |> Repo.preload(:users)

    org_keys = org_with_keys_and_users |> Map.get(:org_keys)
    user_names = org_with_keys_and_users |> Map.get(:users) |> Enum.map(fn x -> x.username end)

    firmwares =
      for v <- firmware_versions,
          do:
            Fixtures.firmware_fixture(Enum.random(org_keys), product, %{
              version: v,
              author: Enum.random(user_names)
            })

    firmwares = firmwares |> List.to_tuple()
      
    Fixtures.deployment_fixture(firmwares |> elem(2), %{
      conditions: %{"version" => "< 1.0.0", "tags" => ["beta"]}
    })
    Firmwares.update_firmware_ttl(elem(firmwares, 2).id)

    Fixtures.device_fixture(org, firmwares |> elem(1))
    |> Fixtures.device_certificate_fixture()
  end

  def nerves_team_seed(root_user_params) do
    org = Fixtures.org_fixture(%{name: "Nerves Team"})

    for _ <- 0..2, do: Fixtures.org_key_fixture(org)

    %{orgs: [default_user_org | _]} =
      Fixtures.user_fixture(root_user_params |> Enum.into(%{orgs: [org]}))

    for _ <- 0..2, do: Fixtures.org_key_fixture(default_user_org)

    ["SmartKiosk", "SmartRentHub"]
    |> Enum.map(fn name -> seed_product(name, org) end)

    ["ToyProject", "ConsultingProject"]
    |> Enum.map(fn name -> seed_product(name, default_user_org) end)
  end
end

# Create the root user
root_user_name = "nerveshub"
root_user_email = "nerveshub@nerves-hub.org"
# Add a default user
if root_user = Repo.get_by(User, email: root_user_email) do
  root_user
else
  if Mix.env() == :dev do
    NervesHubCore.SeedHelpers.nerves_team_seed(%{email: root_user_email, username: root_user_name})
  else
    Accounts.create_user(%{
      username: root_user_name,
      email: root_user_email,
      password: "nerveshub"
    })
  end
end
