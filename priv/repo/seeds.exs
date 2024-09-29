# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     NervesHub.Repo.insert!(%NervesHubWWW.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# The seeds are run on every deploy. Therefore, it is important
# that first check to see if the data you are trying to insert
# has been run yet.
alias NervesHub.{Accounts, Accounts.User, Repo}

defmodule NervesHub.SeedHelpers do
  alias NervesHub.Fixtures

  def seed_product(product_name, user, org) do
    product = Fixtures.product_fixture(user, org, %{name: product_name})

    firmware_versions = ["0.1.0", "0.1.1", "0.1.2", "1.0.0"]

    org_with_keys_and_users =
      org |> NervesHub.Accounts.Org.with_org_keys() |> Repo.preload(:users)

    org_keys = org_with_keys_and_users |> Map.get(:org_keys)
    names = org_with_keys_and_users |> Map.get(:users) |> Enum.map(fn x -> x.name end)

    firmwares =
      for v <- firmware_versions,
          do:
            Fixtures.firmware_fixture(Enum.random(org_keys), product, %{
              version: v,
              author: Enum.random(names)
            })

    firmwares = firmwares |> List.to_tuple()

    Fixtures.deployment_fixture(org_with_keys_and_users, firmwares |> elem(2), %{
      conditions: %{"version" => "< 1.0.0", "tags" => ["beta"]}
    })

    for _ <- 0..15 do
      Fixtures.device_fixture(org, product, firmwares |> elem(1), %{connection_last_seen_at: DateTime.utc_now()})
    end
  end

  def nerves_team_seed(root_user_params) do
    user = Fixtures.user_fixture(root_user_params)

    team = Fixtures.org_fixture(user, %{name: "NervesTeam"})
    personal = Fixtures.org_fixture(user, %{name: "Personal"})

    for _ <- 0..2, do: Fixtures.org_key_fixture(team, user)
    for _ <- 0..2, do: Fixtures.org_key_fixture(personal, user)

    ["SmartKiosk", "SmartRentHub"]
    |> Enum.map(fn name -> seed_product(name, user, team) end)

    ["ToyProject", "ConsultingProject"]
    |> Enum.map(fn name -> seed_product(name, user, personal) end)
  end
end

# Create the root user
root_user_name = "nerveshub"
root_user_email = "nerveshub@nerves-hub.org"
# Add a default user
if root_user = Repo.get_by(User, email: root_user_email) do
  root_user
else
  env =
    if function_exported?(Mix, :env, 0) do
      Mix.env() |> to_string()
    else
      System.get_env("ENVIRONMENT")
    end

  if env == "dev" do
    NervesHub.SeedHelpers.nerves_team_seed(%{
      email: root_user_email,
      username: root_user_name,
      password: root_user_name
    })
  else
    Accounts.create_user(%{
      username: root_user_name,
      email: root_user_email,
      password: "nerveshub"
    })
  end
end
