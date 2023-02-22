defmodule NervesHubWWWWeb.ProductView do
  use NervesHubWWWWeb, :view

  import NervesHubWWWWeb.OrgCertificateView, only: [format_serial: 1]

  def count_results(results, level) do
    Enum.count(results, &match?({_, ^level, _, _}, &1))
  end

  def csv_td_class(changeset, field) do
    cond do
      changeset.errors[field] ->
        "import-warning tooltip-label"

      changeset.data.__meta__.state == :loaded && changeset.changes[field] ->
        "import-updating"

      true ->
        ""
    end
  end
end
