defmodule NervesHubWeb.API.DeviceLogJSON do
  @moduledoc false

  alias NervesHub.Devices.LogLine

  def index(%{log_lines: log_lines}) do
    %{data: for(log_line <- log_lines, do: log_line(log_line))}
  end

  defp log_line(%LogLine{} = log_line) do
    %{
      timestamp: log_line.timestamp,
      level: log_line.level,
      message: log_line.message,
      # Whatever the device attached to the line — Logger metadata, flattened to
      # strings on the way in.
      meta: log_line.meta
    }
  end
end
