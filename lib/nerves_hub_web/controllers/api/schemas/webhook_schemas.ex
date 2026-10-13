defmodule NervesHubWeb.API.Schemas.WebhookSchemas do
  alias NervesHub.Webhooks.Events
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule Webhook do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      description: "A product webhook, without its signing secret",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        url: %Schema{type: :string, description: "Where events are sent"},
        description: %Schema{type: :string, nullable: true, description: "What receives these events"},
        events: %Schema{
          type: :array,
          items: %Schema{type: :string, enum: Events.types()},
          description: "The event types delivered to this webhook"
        },
        enabled: %Schema{type: :boolean, description: "Whether events are being sent"},
        disabled_reason: %Schema{
          type: :string,
          nullable: true,
          description: "Why NervesHub turned the webhook off, if it did. Cleared when it is turned back on."
        },
        failing_since: %Schema{
          type: :string,
          format: :"date-time",
          nullable: true,
          description: "When deliveries started failing, or null while the endpoint is accepting them"
        },
        last_error: %Schema{type: :string, nullable: true, description: "The most recent delivery failure"},
        last_error_at: %Schema{type: :string, format: :"date-time", nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      example: %{
        "id" => 12,
        "url" => "https://hooks.example.com/nerves-hub",
        "description" => "Fleet dashboard",
        "events" => ["device.connected", "device.disconnected"],
        "enabled" => true,
        "disabled_reason" => nil,
        "failing_since" => nil,
        "last_error" => nil,
        "last_error_at" => nil,
        "inserted_at" => "2026-10-13T09:00:00",
        "updated_at" => "2026-10-13T09:00:00"
      }
    })
  end

  defmodule WebhookWithSecret do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      description:
        "A webhook and its signing secret. Only returned when the webhook is created and when its secret is regenerated.",
      allOf: [
        Webhook,
        %Schema{
          type: :object,
          properties: %{
            secret: %Schema{
              type: :string,
              description: "The Standard Webhooks signing secret: `whsec_` followed by base64"
            }
          }
        }
      ],
      example: %{
        "id" => 12,
        "url" => "https://hooks.example.com/nerves-hub",
        "description" => "Fleet dashboard",
        "events" => ["device.connected", "device.disconnected"],
        "enabled" => true,
        "disabled_reason" => nil,
        "failing_since" => nil,
        "last_error" => nil,
        "last_error_at" => nil,
        "inserted_at" => "2026-10-13T09:00:00",
        "updated_at" => "2026-10-13T09:00:00",
        "secret" => "whsec_[44 base64 characters]"
      }
    })
  end

  defmodule WebhookListResponse do
    OpenApiSpex.schema(%{
      description: "The product's webhooks, oldest first",
      type: :object,
      properties: %{data: %Schema{type: :array, items: Webhook}}
    })
  end

  defmodule WebhookResponse do
    OpenApiSpex.schema(%{
      description: "A webhook",
      type: :object,
      properties: %{data: Webhook}
    })
  end

  defmodule WebhookWithSecretResponse do
    OpenApiSpex.schema(%{
      description: "A webhook and its signing secret",
      type: :object,
      properties: %{data: WebhookWithSecret}
    })
  end

  defmodule WebhookCreateRequest do
    OpenApiSpex.schema(%{
      description: "POST body for adding a webhook to a product",
      type: :object,
      properties: %{
        url: %Schema{type: :string, description: "An `https://` or `http://` URL with no username or password"},
        description: %Schema{type: :string, description: "Optional: what receives these events"},
        events: %Schema{
          type: :array,
          items: %Schema{type: :string, enum: Events.types()},
          description: "At least one event type"
        },
        enabled: %Schema{type: :boolean, default: true}
      },
      required: [:url, :events],
      example: %{
        "url" => "https://hooks.example.com/nerves-hub",
        "description" => "Fleet dashboard",
        "events" => ["device.connected", "device.disconnected"]
      }
    })
  end

  defmodule WebhookUpdateRequest do
    OpenApiSpex.schema(%{
      description:
        "PUT/PATCH body for changing a webhook. Omitted fields are left as they are. Turning a webhook on clears what failed deliveries recorded about it.",
      type: :object,
      properties: %{
        url: %Schema{type: :string},
        description: %Schema{type: :string},
        events: %Schema{type: :array, items: %Schema{type: :string, enum: Events.types()}},
        enabled: %Schema{type: :boolean}
      },
      example: %{"events" => ["device.connected"], "enabled" => true}
    })
  end

  defmodule WebhookTestResponse do
    OpenApiSpex.schema(%{
      description: "How the webhook's endpoint answered a `webhook.test` event",
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          properties: %{
            delivered: %Schema{type: :boolean, description: "Whether the endpoint answered with a 2xx status"},
            status: %Schema{
              type: :integer,
              nullable: true,
              description: "The endpoint's response status, or null when there was no response"
            },
            error: %Schema{type: :string, nullable: true, description: "Why the delivery failed, if it did"}
          }
        }
      },
      example: %{"data" => %{"delivered" => false, "status" => 500, "error" => "HTTP 500"}}
    })
  end
end
