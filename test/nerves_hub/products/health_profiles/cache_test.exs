defmodule NervesHub.Products.HealthProfiles.CacheTest do
  # Not async: the cache is one ETS table shared by the whole node, and these
  # tests are about what it holds.
  use NervesHub.DataCase, async: false

  alias NervesHub.Fixtures
  alias NervesHub.Products.HealthProfile
  alias NervesHub.Products.HealthProfiles
  alias NervesHub.Products.HealthProfiles.Cache

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)

    {:ok, %{product: product}}
  end

  describe "resolving through the cache" do
    test "a second resolve does not query", %{product: product} do
      profile = HealthProfiles.resolve(product.id, nil)
      assert %HealthProfile{} = profile

      # Deleted behind the cache's back: a cached answer is the only way this
      # can still come back with the profile.
      Repo.delete_all(HealthProfile)

      assert HealthProfiles.resolve(product.id, nil).id == profile.id
    end

    test "a product with no profile caches the nil too", %{product: product} do
      Repo.delete_all(HealthProfile)
      assert HealthProfiles.resolve(product.id, nil) == nil

      # Re-created behind the cache's back; the cached nil still stands.
      {:ok, _} = HealthProfiles.create_default_profile(product.id)
      Cache.reset()
      assert %HealthProfile{} = HealthProfiles.resolve(product.id, nil)
    end

    test "platform and default are cached separately", %{product: product} do
      {:ok, _} = HealthProfiles.create_platform_profile(product, "rpi4")

      assert HealthProfiles.resolve(product.id, "rpi4").platform == "rpi4"
      assert HealthProfiles.resolve(product.id, nil).platform == nil
      assert HealthProfiles.resolve(product.id, "rpi0").platform == nil
    end
  end

  describe "invalidation" do
    test "editing a metric is visible to the next resolve", %{product: product} do
      profile = HealthProfiles.resolve(product.id, nil)
      cpu = Enum.find(profile.metrics, &(&1.key == "cpu_usage_percent"))

      {:ok, _} = HealthProfiles.update_metric(cpu, %{"warning_threshold" => "42"})

      reloaded = HealthProfiles.resolve(product.id, nil)
      assert Enum.find(reloaded.metrics, &(&1.key == "cpu_usage_percent")).warning_threshold == 42.0
    end

    test "adding and removing a metric is visible to the next resolve", %{product: product} do
      profile = HealthProfiles.resolve(product.id, nil)

      {:ok, metric} =
        HealthProfiles.add_metric(profile, %{
          "key" => "water_temp",
          "warning_threshold" => "50",
          "warning_period_seconds" => "3600",
          "alert_threshold" => "90",
          "alert_period_seconds" => "3600"
        })

      assert "water_temp" in Enum.map(HealthProfiles.resolve(product.id, nil).metrics, & &1.key)

      :ok = HealthProfiles.delete_metric(metric)

      refute "water_temp" in Enum.map(HealthProfiles.resolve(product.id, nil).metrics, & &1.key)
    end

    test "deleting a platform profile falls the platform back to the default", %{product: product} do
      {:ok, platform_profile} = HealthProfiles.create_platform_profile(product, "rpi4")
      assert HealthProfiles.resolve(product.id, "rpi4").platform == "rpi4"

      {:ok, _} = HealthProfiles.delete_profile(platform_profile)

      assert HealthProfiles.resolve(product.id, "rpi4").platform == nil
    end

    test "a failed write leaves the cache alone", %{product: product} do
      profile = HealthProfiles.resolve(product.id, nil)
      cpu = Enum.find(profile.metrics, &(&1.key == "cpu_usage_percent"))

      # Alert below warning, with high unhealthy: rejected.
      {:error, _changeset} = HealthProfiles.update_metric(cpu, %{"alert_threshold" => "1"})

      assert HealthProfiles.resolve(product.id, nil).id == profile.id
    end

    test "only the edited product is dropped", %{product: product} do
      other = Fixtures.product_fixture(Fixtures.user_fixture(), Fixtures.org_fixture(Fixtures.user_fixture()))

      _ = HealthProfiles.resolve(other.id, nil)
      profile = HealthProfiles.resolve(product.id, nil)
      cpu = Enum.find(profile.metrics, &(&1.key == "cpu_usage_percent"))

      {:ok, _} = HealthProfiles.update_metric(cpu, %{"warning_threshold" => "42"})

      # The other product's entry survived: deleting its rows cannot change
      # what a cached resolve answers.
      other_id = other.id
      Repo.delete_all(from(p in HealthProfile, where: p.product_id == ^other_id))

      assert %HealthProfile{} = HealthProfiles.resolve(other.id, nil)
    end
  end

  describe "a miss" do
    test "computes and stores the value" do
      assert Cache.fetch({-1, nil}, fn -> :computed end) == :computed
      assert Cache.fetch({-1, nil}, fn -> :not_called end) == :computed
    end
  end
end
