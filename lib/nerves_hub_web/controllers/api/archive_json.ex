defmodule NervesHubWeb.API.ArchiveJSON do
  @moduledoc false

  def index(%{archives: archives}) do
    %{data: for(archive <- archives, do: archive(archive))}
  end

  def show(%{archive: archive}) do
    %{data: archive(archive)}
  end

  defp archive(archive) do
    %{
      uuid: archive.uuid,
      version: archive.version,
      platform: archive.platform,
      architecture: archive.architecture,
      author: archive.author,
      description: archive.description,
      misc: archive.misc,
      vcs_identifier: archive.vcs_identifier,
      size: archive.size,
      inserted_at: archive.inserted_at
    }
  end
end
