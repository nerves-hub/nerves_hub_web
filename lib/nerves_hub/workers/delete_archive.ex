defmodule NervesHub.Workers.DeleteArchive do
  use Oban.Worker,
    queue: :delete_file,
    max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"archive_path" => path}}) do
    backend = Application.fetch_env!(:nerves_hub, NervesHub.Uploads)[:backend]

    backend.delete(path)
  end
end
