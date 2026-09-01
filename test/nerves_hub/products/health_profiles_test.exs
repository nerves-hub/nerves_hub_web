defmodule NervesHub.Products.HealthProfilesTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Devices.Device
  alias NervesHub.Fixtures
  alias NervesHub.Products
  alias NervesHub.Products.HealthProfile
  alias NervesHub.Products.HealthProfiles
  alias NervesHub.Products.Product

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)

    {:ok, %{user: user, org: org, product: product}}
  end

  describe "default profile" do
    test "creating a product creates its default profile with the default metrics", %{product: product} do
      assert [profile] = HealthProfiles.all_for_product(product)
      assert profile.platform == nil

      assert Enum.map(profile.metrics, &{&1.key, &1.warning_threshold, &1.alert_threshold}) == [
               {"cpu_usage_percent", 80.0, 90.0},
               {"disk_used_percentage", 80.0, 90.0},
               {"mem_used_percent", 70.0, 80.0}
             ]

      assert Enum.all?(profile.metrics, &(&1.warning_period_seconds == 3600 and &1.alert_period_seconds == 3600))
      refute Enum.any?(profile.metrics, & &1.built_in)

      # The starting metrics are the ones the device details page features.
      assert Enum.all?(profile.metrics, & &1.featured)
    end

    test "the default profile cannot be deleted", %{product: product} do
      [profile] = HealthProfiles.all_for_product(product)

      assert {:error, :cannot_delete_default} = HealthProfiles.delete_profile(profile)
      assert [_profile] = HealthProfiles.all_for_product(product)
    end

    test "a product cannot get a second default profile", %{product: product} do
      assert {:error, changeset} = HealthProfiles.create_default_profile(product.id)
      assert %{platform: ["already has a health profile"]} = errors_on(changeset)
    end
  end

  describe "platform profiles" do
    test "starts as a copy of the default profile", %{product: product} do
      default = HealthProfiles.resolve(product.id, nil)
      cpu = Enum.find(default.metrics, &(&1.key == "cpu_usage_percent"))

      {:ok, _} =
        HealthProfiles.update_metric(cpu, %{"warning_threshold" => 50, "alert_threshold" => 60, "featured" => "false"})

      assert {:ok, profile} = HealthProfiles.create_platform_profile(product, "rpi4")

      assert profile.platform == "rpi4"
      copied = Enum.find(profile.metrics, &(&1.key == "cpu_usage_percent"))
      assert copied.warning_threshold == 50.0
      assert copied.alert_threshold == 60.0
      assert copied.featured == false
    end

    test "one profile per platform", %{product: product} do
      {:ok, _} = HealthProfiles.create_platform_profile(product, "rpi4")

      assert {:error, changeset} = HealthProfiles.create_platform_profile(product, "rpi4")
      assert %{platform: ["already has a health profile"]} = errors_on(changeset)
    end

    test "can be deleted", %{product: product} do
      {:ok, profile} = HealthProfiles.create_platform_profile(product, "rpi4")

      assert {:ok, _} = HealthProfiles.delete_profile(profile)
      assert [%{platform: nil}] = HealthProfiles.all_for_product(product)
    end
  end

  describe "resolve/2" do
    test "platform profile wins over the default for its platform", %{product: product} do
      {:ok, platform_profile} = HealthProfiles.create_platform_profile(product, "rpi4")

      assert HealthProfiles.resolve(product.id, "rpi4").id == platform_profile.id
      assert HealthProfiles.resolve(product.id, "rpi0").platform == nil
      assert HealthProfiles.resolve(product.id, nil).platform == nil
    end

    test "nil for a product without profiles", %{product: product} do
      Repo.delete_all(HealthProfile)

      assert HealthProfiles.resolve(product.id, "rpi4") == nil
    end
  end

  describe "profile metrics" do
    setup %{product: product} do
      {:ok, %{profile: HealthProfiles.resolve(product.id, nil)}}
    end

    test "adding a device-reported metric", %{profile: profile} do
      attrs = %{
        "key" => "cpu_temp",
        "warning_threshold" => "70",
        "warning_period_seconds" => "1800",
        "alert_threshold" => "85",
        "alert_period_seconds" => "300"
      }

      assert {:ok, metric} = HealthProfiles.add_metric(profile, attrs)
      assert metric.built_in == false
      assert metric.featured == false
      assert metric.warning_threshold == 70.0
      assert metric.alert_period_seconds == 300
    end

    test "a metric can be added as featured, and toggled later", %{profile: profile, product: product} do
      attrs = Map.put(valid_metric_attrs("cpu_temp"), "featured", "true")

      assert {:ok, metric} = HealthProfiles.add_metric(profile, attrs)
      assert metric.featured == true

      assert {:ok, metric} = HealthProfiles.update_metric(metric, %{"featured" => "false"})
      assert metric.featured == false

      # featured_keys reports the featured, non-built-in keys of the resolved profile
      assert HealthProfiles.featured_keys(product.id, nil) |> Enum.sort() ==
               ["cpu_usage_percent", "disk_used_percentage", "mem_used_percent"]
    end

    test "a built-in key is flagged from the registry, not the caller", %{profile: profile} do
      attrs = %{
        "key" => "disconnects",
        # A caller cannot un-flag a built-in.
        "built_in" => "false",
        "warning_threshold" => "5",
        "warning_period_seconds" => "3600",
        "alert_threshold" => "10",
        "alert_period_seconds" => "3600"
      }

      assert {:ok, metric} = HealthProfiles.add_metric(profile, attrs)
      assert metric.built_in == true
    end

    test "a low-is-unhealthy metric flips the threshold ordering rule", %{profile: profile} do
      lte = %{
        "key" => "fps",
        "operator" => "lte",
        "warning_threshold" => "25",
        "warning_period_seconds" => "3600",
        "alert_threshold" => "15",
        "alert_period_seconds" => "3600"
      }

      assert {:ok, metric} = HealthProfiles.add_metric(profile, lte)
      assert metric.operator == :lte

      # With low unhealthy, an alert above the warning would engage last.
      inverted = Map.merge(lte, %{"key" => "fps2", "alert_threshold" => "30"})

      assert {:error, changeset} = HealthProfiles.add_metric(profile, inverted)

      assert %{alert_threshold: ["must be at or below the warning threshold when low is unhealthy"]} =
               errors_on(changeset)
    end

    test "a built-in's operator is not the caller's to choose", %{profile: profile} do
      attrs = %{
        "key" => "disconnects",
        "operator" => "lte",
        "warning_threshold" => "3",
        "warning_period_seconds" => "3600",
        "alert_threshold" => "5",
        "alert_period_seconds" => "3600"
      }

      assert {:ok, metric} = HealthProfiles.add_metric(profile, attrs)
      assert metric.operator == :gte

      assert {:ok, metric} = HealthProfiles.update_metric(metric, %{"operator" => "lte"})
      assert metric.operator == :gte
    end

    test "a key can only appear once per profile", %{profile: profile} do
      attrs = valid_metric_attrs("cpu_temp")

      assert {:ok, _} = HealthProfiles.add_metric(profile, attrs)
      assert {:error, changeset} = HealthProfiles.add_metric(profile, attrs)
      assert %{key: ["is already in this profile"]} = errors_on(changeset)
    end

    test "the alert threshold cannot sit below the warning threshold", %{profile: profile} do
      attrs = Map.merge(valid_metric_attrs("cpu_temp"), %{"warning_threshold" => "80", "alert_threshold" => "70"})

      assert {:error, changeset} = HealthProfiles.add_metric(profile, attrs)
      assert %{alert_threshold: [error]} = errors_on(changeset)
      assert error =~ "warning threshold"
    end

    test "measurement periods stay between 1 minute and 24 hours", %{profile: profile} do
      over = Map.put(valid_metric_attrs("cpu_temp"), "alert_period_seconds", "#{25 * 3600}")

      assert {:error, changeset} = HealthProfiles.add_metric(profile, over)
      assert %{alert_period_seconds: ["must be between 1 minute and 24 hours"]} = errors_on(changeset)

      under = Map.put(valid_metric_attrs("cpu_temp"), "warning_period_seconds", "30")

      assert {:error, changeset} = HealthProfiles.add_metric(profile, under)
      assert %{warning_period_seconds: ["must be between 1 minute and 24 hours"]} = errors_on(changeset)
    end

    test "updating cannot change the key", %{profile: profile} do
      {:ok, metric} = HealthProfiles.add_metric(profile, valid_metric_attrs("cpu_temp"))

      assert {:ok, updated} =
               HealthProfiles.update_metric(metric, %{
                 "key" => "other",
                 "warning_threshold" => "10",
                 "alert_threshold" => "20"
               })

      assert updated.key == "cpu_temp"
      assert updated.warning_threshold == 10.0
    end

    test "deleting a metric", %{profile: profile, product: product} do
      {:ok, metric} = HealthProfiles.add_metric(profile, valid_metric_attrs("cpu_temp"))

      assert :ok = HealthProfiles.delete_metric(metric)

      refute product.id
             |> HealthProfiles.resolve(nil)
             |> Map.fetch!(:metrics)
             |> Enum.any?(&(&1.key == "cpu_temp"))
    end
  end

  test "deleting a product removes its profiles", %{product: product} do
    {:ok, _} = Products.delete_product(product)

    # Soft delete: profiles stay until the product row goes, but a hard delete
    # cascades.
    Repo.delete_all(Device)
    Repo.delete(%Product{id: product.id})

    assert HealthProfiles.all_for_product(product) == []
  end

  defp valid_metric_attrs(key) do
    %{
      "key" => key,
      "warning_threshold" => "70",
      "warning_period_seconds" => "3600",
      "alert_threshold" => "85",
      "alert_period_seconds" => "3600"
    }
  end
end
