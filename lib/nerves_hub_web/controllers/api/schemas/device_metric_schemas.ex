defmodule NervesHubWeb.API.Schemas.DeviceMetricSchemas do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule DeviceMetricReport do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      description: "One metrics report from a device: the readings it took at one moment",
      type: :object,
      properties: %{
        timestamp: %Schema{
          type: :string,
          format: :"date-time",
          description: "When the device took the readings, to microsecond precision"
        },
        firmware_uuid: %Schema{
          type: :string,
          nullable: true,
          description: "The firmware the device was running when it took the readings, if it had reported one"
        },
        metrics: %Schema{
          type: :object,
          description: "The readings, keyed by the device's own metric names",
          additionalProperties: %Schema{type: :number}
        }
      },
      example: %{
        "timestamp" => "2026-08-16T09:14:00.123456Z",
        "firmware_uuid" => "8f6c3a1e-2b7d-4c55-9e0a-1d2f3b4c5a6e",
        "metrics" => %{"cpu_temp" => 41.2, "mem_used_percent" => 38.0}
      }
    })
  end

  defmodule DeviceMetricReportListResponse do
    OpenApiSpex.schema(%{
      description: "Device metric report list response",
      type: :object,
      properties: %{
        data: %Schema{
          description: "The matching reports, newest first unless `order=asc` was given",
          type: :array,
          items: DeviceMetricReport
        }
      },
      example: %{
        "data" => [
          %{
            "timestamp" => "2026-08-16T09:14:00.123456Z",
            "firmware_uuid" => "8f6c3a1e-2b7d-4c55-9e0a-1d2f3b4c5a6e",
            "metrics" => %{"cpu_temp" => 41.9, "mem_used_percent" => 38.5}
          },
          %{
            "timestamp" => "2026-08-16T09:13:00.004210Z",
            "firmware_uuid" => "8f6c3a1e-2b7d-4c55-9e0a-1d2f3b4c5a6e",
            "metrics" => %{"cpu_temp" => 41.2, "mem_used_percent" => 38.0}
          }
        ]
      }
    })
  end
end
