defmodule NervesHub.Products.HealthProfilesTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.Health
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
               {"load_15min", 8.0, 10.0},
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

    test "count_for_product/1 counts the default and each platform profile", %{product: product} do
      assert HealthProfiles.count_for_product(product) == 1

      {:ok, _profile} = HealthProfiles.create_platform_profile(product, "rpi4")

      assert HealthProfiles.count_for_product(product) == 2
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

  describe "save_metrics/2" do
    setup %{product: product} do
      {:ok, %{profile: HealthProfiles.resolve(product.id, nil)}}
    end

    test "updates, adds and removes metrics in one save", %{profile: profile, product: product} do
      [cpu, disk | _] = Enum.sort_by(profile.metrics, & &1.key)
      kept = profile.metrics -- [disk]

      metrics =
        Enum.map(kept, fn metric ->
          attrs = metric_attrs(metric)
          if metric.id == cpu.id, do: %{attrs | "warning_threshold" => "55", "featured" => false}, else: attrs
        end) ++ [Map.put(valid_metric_attrs("cpu_temp"), "operator", "lte") |> Map.put("alert_threshold", "60")]

      assert {:ok, saved} = HealthProfiles.save_metrics(profile, metrics)

      keys = Enum.map(saved.metrics, & &1.key)
      assert "cpu_temp" in keys
      refute disk.key in keys

      saved_cpu = Enum.find(saved.metrics, &(&1.id == cpu.id))
      assert saved_cpu.warning_threshold == 55.0
      assert saved_cpu.featured == false
      assert Enum.find(saved.metrics, &(&1.key == "cpu_temp")).operator == :lte

      # The cache was dropped, so evaluation sees the save straight away.
      assert product.id |> HealthProfiles.resolve(nil) |> Map.fetch!(:metrics) |> length() == length(saved.metrics)
    end

    test "saves nothing when one metric doesn't validate, and says which", %{profile: profile} do
      # Changes a kept metric too, which mustn't be saved either.
      [first | rest] = profile.metrics
      bad = %{valid_metric_attrs("cpu_temp") | "alert_threshold" => "10"}
      metrics = [%{metric_attrs(first) | "warning_threshold" => "1"} | Enum.map(rest, &metric_attrs/1)] ++ [bad]

      assert {:error, index, changeset} = HealthProfiles.save_metrics(profile, metrics)
      assert index == length(profile.metrics)
      assert %{alert_threshold: [_]} = errors_on(changeset)

      saved = HealthProfiles.resolve(profile.product_id, nil)
      refute Enum.any?(saved.metrics, &(&1.key == "cpu_temp"))
      assert Enum.find(saved.metrics, &(&1.id == first.id)).warning_threshold == first.warning_threshold
    end

    test "a metric removed and added back in one save is replaced", %{profile: profile} do
      [cpu | rest] = Enum.sort_by(profile.metrics, & &1.key)
      readded = cpu |> metric_attrs() |> Map.delete("id") |> Map.put("warning_threshold", "42")

      assert {:ok, saved} = HealthProfiles.save_metrics(profile, Enum.map(rest, &metric_attrs/1) ++ [readded])

      new_cpu = Enum.find(saved.metrics, &(&1.key == cpu.key))
      assert new_cpu.id != cpu.id
      assert new_cpu.warning_threshold == 42.0
    end

    test "can't touch another profile's metrics", %{profile: profile, product: product} do
      {:ok, other} = HealthProfiles.create_platform_profile(product, "rpi4")
      foreign = hd(other.metrics)

      # An id from another profile is treated as a new metric for this one.
      attrs = foreign |> metric_attrs() |> Map.put("key", "cpu_temp")
      assert {:ok, _} = HealthProfiles.save_metrics(profile, Enum.map(profile.metrics, &metric_attrs/1) ++ [attrs])

      assert Repo.reload(foreign).key == foreign.key
    end

    test "a built-in keeps its direction", %{profile: profile} do
      disconnects = %{valid_metric_attrs("disconnects") | "warning_threshold" => "3", "alert_threshold" => "10"}

      assert {:ok, saved} =
               HealthProfiles.save_metrics(
                 profile,
                 Enum.map(profile.metrics, &metric_attrs/1) ++ [Map.put(disconnects, "operator", "lte")]
               )

      metric = Enum.find(saved.metrics, &(&1.key == "disconnects"))
      assert metric.built_in
      assert metric.operator == :gte
    end
  end

  describe "device_counts/3 and health_counts/4" do
    @describetag :tmp_dir

    setup %{user: user, org: org, product: product, tmp_dir: tmp_dir} do
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      {:ok, %{firmware: firmware}}
    end

    test "count each profile's devices, and their health", %{user: user, org: org, product: product, firmware: firmware} do
      [warning, _unknown] = for _ <- 1..2, do: Fixtures.device_fixture(org, product, firmware)
      org |> Fixtures.device_fixture(product, firmware) |> on_platform("esp32")

      # A deleted device counts nowhere.
      org
      |> Fixtures.device_fixture(product, firmware)
      |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second))
      |> Repo.update!()

      {:ok, _} = Health.save_device_health(%{"device_id" => warning.id, "status" => :warning})

      {:ok, esp32_profile} = HealthProfiles.create_platform_profile(product, "esp32")
      profiles = HealthProfiles.all_for_product(product)
      default = Enum.find(profiles, &is_nil(&1.platform))

      assert HealthProfiles.device_counts(product, user, profiles) == %{nil => 2, "esp32" => 1}

      assert HealthProfiles.health_counts(product, user, default, profiles) ==
               %{healthy: 0, warning: 1, unhealthy: 0, unknown: 1}

      assert HealthProfiles.health_counts(product, user, esp32_profile, profiles) ==
               %{healthy: 0, warning: 0, unhealthy: 0, unknown: 1}

      # Without a profile of its own, the esp32 device falls to Default.
      {:ok, _} = HealthProfiles.delete_profile(esp32_profile)
      assert HealthProfiles.device_counts(product, user, HealthProfiles.all_for_product(product)) == %{nil => 3}
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
      assert HealthProfiles.featured_keys(%{product_id: product.id}) |> Enum.sort() ==
               ["cpu_usage_percent", "disk_used_percentage", "load_15min", "mem_used_percent"]
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

  describe "suggested_thresholds/1" do
    # A history that clears every gate: over a week old, plenty of samples,
    # quartiles 20 and 40 (IQR 20).
    defp stats(overrides \\ []) do
      Map.merge(
        %{
          min: 5.0,
          max: 60.0,
          q1: 20.0,
          q3: 40.0,
          samples: 200,
          oldest: DateTime.add(DateTime.utc_now(), -8, :day)
        },
        Map.new(overrides)
      )
    end

    test "suggests Tukey's fences in both directions" do
      assert HealthProfiles.suggested_thresholds(stats()) == %{
               gte: %{warning: 70.0, alert: 100.0},
               lte: %{warning: -10.0, alert: -40.0}
             }
    end

    test "no suggestion without stats, a week of history, enough samples, or any spread" do
      assert HealthProfiles.suggested_thresholds(nil) == nil

      six_days = DateTime.add(DateTime.utc_now(), -6, :day)
      assert HealthProfiles.suggested_thresholds(stats(oldest: six_days)) == nil

      assert HealthProfiles.suggested_thresholds(stats(samples: 99)) == nil

      # Zero IQR: the fences would sit on the median, where half of all
      # normal samples already "breach".
      assert HealthProfiles.suggested_thresholds(stats(q1: 42.0, q3: 42.0)) == nil
    end

    test "suggestions are rounded to three significant digits" do
      %{gte: gte} = HealthProfiles.suggested_thresholds(stats(q1: 10.111, q3: 30.333))
      assert gte == %{warning: 60.7, alert: 91.0}

      %{gte: big} = HealthProfiles.suggested_thresholds(stats(q1: 1_000_000.0, q3: 2_345_678.0))
      assert big.warning == 4_360_000.0
    end
  end

  defp metric_attrs(metric) do
    %{
      "id" => metric.id,
      "key" => metric.key,
      "featured" => metric.featured,
      "operator" => to_string(metric.operator),
      "warning_threshold" => to_string(metric.warning_threshold),
      "warning_period_seconds" => metric.warning_period_seconds,
      "alert_threshold" => to_string(metric.alert_threshold),
      "alert_period_seconds" => metric.alert_period_seconds
    }
  end

  defp on_platform(device, platform) do
    device
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_embed(:firmware_metadata, Ecto.Changeset.change(device.firmware_metadata, platform: platform))
    |> Repo.update!()
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
