defmodule NervesHub.Tracer do
  @moduledoc false

  defmacro trace(name, device, do: block) do
    quote do
      OpenTelemetry.Tracer.with_span unquote(name) do
        OpenTelemetry.Tracer.set_attributes(%{
          "nerves_hub.device.id" => unquote(device).id,
          "nerves_hub.device.identifier" => unquote(device).identifier
        })

        unquote(block)
      end
    end
  end
end
