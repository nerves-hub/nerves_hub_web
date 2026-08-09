defmodule Mix.Tasks.NervesHub.Versions.ReportInvalid do
  @shortdoc "Report firmware/archive rows whose version is not valid SemVer"

  @moduledoc """
  Reports existing `firmwares` and `archives` rows whose `version` does not parse
  as SemVer according to `Version.parse/1`.

  Version validation is enforced on new firmware/archive at the schema boundary,
  but pre-existing rows are not retro-rejected. Such rows produce a NULL
  `semver_sort_key/1` and therefore sort last (with `NULLS LAST`) and never match
  a version constraint. This read-only task surfaces them so they can be cleaned
  up. It changes nothing.

  ## Examples

      mix nerves_hub.versions.report_invalid
  """

  use Mix.Task

  import Ecto.Query

  alias NervesHub.Archives.Archive
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Repo

  @requirements ["app.start"]
  @preferred_cli_env :dev

  @impl Mix.Task
  def run(_args) do
    report("firmwares", Firmware)
    report("archives", Archive)
  end

  defp report(label, schema) do
    invalid =
      schema
      |> select([r], %{id: r.id, product_id: r.product_id, uuid: r.uuid, version: r.version})
      |> Repo.all()
      |> Enum.reject(&valid_semver?(&1.version))

    case invalid do
      [] ->
        Mix.shell().info("#{label}: no invalid versions")

      rows ->
        Mix.shell().info("#{label}: #{length(rows)} invalid version(s)")

        Enum.each(rows, fn r ->
          Mix.shell().info("  id=#{r.id} product_id=#{r.product_id} uuid=#{r.uuid} version=#{inspect(r.version)}")
        end)
    end
  end

  defp valid_semver?(version) when is_binary(version) do
    match?({:ok, _}, Version.parse(version))
  end

  defp valid_semver?(_), do: false
end
