defmodule NervesHubWeb.API.Schemas.DeviceLogSchemas do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule DeviceLogLine do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      description: "A log line a device sent over the logging extension",
      type: :object,
      properties: %{
        timestamp: %Schema{
          type: :string,
          format: :"date-time",
          description: "When the device logged the line, to microsecond precision"
        },
        level: %Schema{
          type: :string,
          description:
            "The level the device logged at. Usually an Elixir Logger level — debug, info, notice, warning, error, critical, alert, emergency — but a device can log at any level it likes",
          example: "error"
        },
        message: %Schema{type: :string, description: "The logged message"},
        meta: %Schema{
          type: :object,
          description: "The Logger metadata the device attached to the line, flattened to strings",
          additionalProperties: %Schema{type: :string}
        }
      },
      example: %{
        "timestamp" => "2026-08-16T09:14:00.123456Z",
        "level" => "error",
        "message" => "Failed to reach the sensor bus",
        "meta" => %{"file" => "lib/thermostat/sensors.ex", "line" => "42"}
      }
    })
  end

  defmodule DeviceLogListResponse do
    OpenApiSpex.schema(%{
      description: "Device log list response",
      type: :object,
      properties: %{
        data: %Schema{
          description: "The matching log lines, newest first unless `order=asc` was given",
          type: :array,
          items: DeviceLogLine
        }
      },
      example: %{
        "data" => [
          %{
            "timestamp" => "2026-08-16T09:14:00.123456Z",
            "level" => "error",
            "message" => "Failed to reach the sensor bus",
            "meta" => %{"file" => "lib/thermostat/sensors.ex", "line" => "42"}
          },
          %{
            "timestamp" => "2026-08-16T09:13:59.998211Z",
            "level" => "info",
            "message" => "Starting sensor poll",
            "meta" => %{}
          }
        ]
      }
    })
  end
end
