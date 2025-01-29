defmodule NervesHub.Devices.HealthStatusTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Devices.HealthStatus

  setup do
    {:ok, %{thresholds: HealthStatus.default_thresholds()}}
  end

  describe "get device status from metrics map" do
    test "status is unknown - no metrics" do
      assert :unknown = HealthStatus.calculate_metrics_status(%{})
    end

    test "status is unknown - metrics without thresholds" do
      metrics = %{
        "other_metric" => 45
      }

      assert :unknown = HealthStatus.calculate_metrics_status(metrics)
    end

    test "status is healthy", %{thresholds: thresholds} do
      metrics = %{
        "cpu_usage_percent" => below_warning(thresholds, "cpu_usage_percent"),
        "mem_used_percent" => below_warning(thresholds, "mem_used_percent")
      }

      assert :healthy = HealthStatus.calculate_metrics_status(metrics)
    end

    test "status is healthy - with unknown metrics", %{
      thresholds: thresholds
    } do
      metrics = %{
        "cpu_usage_percent" => below_warning(thresholds, "cpu_usage_percent"),
        "mem_used_percent" => below_warning(thresholds, "mem_used_percent"),
        "unknown" => 12
      }

      assert :healthy = HealthStatus.calculate_metrics_status(metrics)
    end

    test "status is warning", %{thresholds: thresholds} do
      cpu_warning = warning(thresholds, "cpu_usage_percent")

      metrics = %{
        "cpu_usage_percent" => cpu_warning,
        "mem_used_percent" => below_warning(thresholds, "mem_used_percent")
      }

      expected_warnings =
        %{
          "cpu_usage_percent" => %{
            value: cpu_warning,
            threshold: cpu_warning
          }
        }

      assert {:warning, %{warning: expected_warnings, unhealthy: %{}}} ==
               HealthStatus.calculate_metrics_status(metrics)
    end

    test "status is warning - reports multiple warnings", %{
      thresholds: thresholds
    } do
      cpu_warning = warning(thresholds, "cpu_usage_percent")
      mem_warning = warning(thresholds, "mem_used_percent")

      metrics = %{
        "cpu_usage_percent" => cpu_warning,
        "mem_used_percent" => mem_warning,
        "disk_used_percentage" => below_warning(thresholds, "disk_used_percentage")
      }

      expected_warnings =
        %{
          "cpu_usage_percent" => %{
            value: cpu_warning,
            threshold: cpu_warning
          },
          "mem_used_percent" => %{
            value: mem_warning,
            threshold: mem_warning
          }
        }

      assert {:warning, %{warning: expected_warnings, unhealthy: %{}}} ==
               HealthStatus.calculate_metrics_status(metrics)
    end

    test "status is unhealthy", %{thresholds: thresholds} do
      mem_unhealthy = unhealthy(thresholds, "mem_used_percent")

      metrics = %{
        "cpu_usage_percent" => below_warning(thresholds, "cpu_usage_percent"),
        "mem_used_percent" => mem_unhealthy,
        "disk_used_percentage" => below_warning(thresholds, "disk_used_percentage")
      }

      expected_unhealthy =
        %{
          "mem_used_percent" => %{
            value: mem_unhealthy,
            threshold: mem_unhealthy
          }
        }

      assert {:unhealthy, %{warning: %{}, unhealthy: expected_unhealthy}} ==
               HealthStatus.calculate_metrics_status(metrics)
    end

    test "status is unhealthy - reports multiple unhealthy metrics", %{
      thresholds: thresholds
    } do
      mem_unhealthy = unhealthy(thresholds, "mem_used_percent")
      disk_unhealthy = unhealthy(thresholds, "disk_used_percentage")

      metrics = %{
        "cpu_usage_percent" => below_warning(thresholds, "cpu_usage_percent"),
        "mem_used_percent" => mem_unhealthy,
        "disk_used_percentage" => disk_unhealthy
      }

      expected_unhealthy =
        %{
          "mem_used_percent" => %{
            value: mem_unhealthy,
            threshold: mem_unhealthy
          },
          "disk_used_percentage" => %{
            value: disk_unhealthy,
            threshold: disk_unhealthy
          }
        }

      assert {:unhealthy, %{warning: %{}, unhealthy: expected_unhealthy}} ==
               HealthStatus.calculate_metrics_status(metrics)
    end

    test "status is unhealthy - also reports warnings", %{
      thresholds: thresholds
    } do
      mem_unhealthy = unhealthy(thresholds, "mem_used_percent")
      disk_warning = warning(thresholds, "disk_used_percentage")

      metrics = %{
        "cpu_usage_percent" => below_warning(thresholds, "cpu_usage_percent"),
        "mem_used_percent" => mem_unhealthy,
        "disk_used_percentage" => disk_warning
      }

      expected_unhealthy =
        %{
          "mem_used_percent" => %{
            value: mem_unhealthy,
            threshold: mem_unhealthy
          }
        }

      expected_warnings = %{
        "disk_used_percentage" => %{
          value: disk_warning,
          threshold: disk_warning
        }
      }

      assert {:unhealthy, %{warning: expected_warnings, unhealthy: expected_unhealthy}} ==
               HealthStatus.calculate_metrics_status(metrics)
    end
  end

  defp unhealthy(thresholds, key), do: thresholds[key].unhealthy
  defp warning(thresholds, key), do: thresholds[key].warning
  defp below_warning(thresholds, key), do: thresholds[key].warning - 1
end
