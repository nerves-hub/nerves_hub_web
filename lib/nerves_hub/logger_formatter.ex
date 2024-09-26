defmodule NervesHub.LoggerFormatter do
  @pattern Logger.Formatter.compile("$time [$level] $metadata$message\n")
  def format(level, message, timestamp, metadata) do
    metadata = Keyword.drop(metadata, [:line, :file, :domain, :application, :mfa, :pid])
    Logger.Formatter.format(@pattern, level, message, timestamp, metadata)
  end
end
