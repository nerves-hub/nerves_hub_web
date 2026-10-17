defmodule NervesHubWeb.LayoutView do
  use NervesHubWeb, :view

  alias NervesHub.Helpers.RelativeTime

  @tib :math.pow(2, 40)
  @gib :math.pow(2, 30)
  @mib :math.pow(2, 20)
  @kib :math.pow(2, 10)
  @precision 2

  @doc """
  Note that results are in multiples of unit bytes: KiB, MiB, GiB
  [Wikipedia](https://en.wikipedia.org/wiki/Binary_prefix)
  """
  def humanize_size(bytes) do
    cond do
      bytes > @tib -> "#{Float.round(bytes / @gib, @precision)} TB"
      bytes > @gib -> "#{Float.round(bytes / @gib, @precision)} GB"
      bytes > @mib -> "#{Float.round(bytes / @mib, @precision)} MB"
      bytes > @kib -> "#{Float.round(bytes / @kib, @precision)} KB"
      true -> "#{bytes} bytes"
    end
  end

  defmodule DateTimeFormat do
    def from_now(%DateTime{} = timestamp), do: RelativeTime.from_now(timestamp)
    def from_now(%NaiveDateTime{} = timestamp), do: RelativeTime.from_now(timestamp)
    def from_now(timestamp), do: timestamp
  end
end
