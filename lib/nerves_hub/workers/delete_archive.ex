defmodule NervesHub.Workers.DeleteArchive do
  use Oban.Worker,
    queue: :delete_file,
    max_attempts: 5

  alias NervesHub.Archives

  # An archive uploaded before archives were stored under their org and product
  # can share its file with another archive with the same UUID, and an archive
  # deleted and uploaded again uses the same path as before. Either way the
  # file still belongs to an archive, so it stays.
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"archive_path" => path}}) do
    if Archives.file_in_use?(path) do
      :ok
    else
      NervesHub.Uploads.delete(path)
    end
  end
end
