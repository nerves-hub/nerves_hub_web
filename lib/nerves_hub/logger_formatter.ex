defmodule NervesHub.LoggerFormatter do
  @metadata_ignore_list [:line, :file, :domain, :application, :pid, :mfa]
  @pattern Logger.Formatter.compile("$time [$level] $metadata$message\n")

  def format(level, message, timestamp, metadata) do
    metadata = Keyword.drop(metadata, ignore_list())
    Logger.Formatter.format(@pattern, level, message, timestamp, metadata)
  end

  defp ignore_list() do
    if Application.get_env(:nerves_hub, :log_include_mfa) do
      @metadata_ignore_list -- [:mfa]
    else
      @metadata_ignore_list
    end
  end
end
