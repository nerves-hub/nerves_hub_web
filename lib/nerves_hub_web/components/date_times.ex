defmodule NervesHubWeb.Components.DateTimes do
  @moduledoc """
  Renders stored timestamps in the viewer's own time zone.

  Everything NervesHub stores is UTC. `local_datetime/1` shifts a timestamp into
  the zone assigned by `NervesHubWeb.Mounts.SetUsersTimezone` and renders a
  `<time>` element that keeps the original UTC value in its `title`, so a reader
  can still line a row up against device logs or an API response.
  """

  use Phoenix.Component

  alias NervesHub.Helpers.RelativeTime
  alias NervesHubWeb.Helpers.Timezone

  # Zone-abbreviation suffixes are appended separately rather than via `%Z`, so a
  # caller can drop the label where the surrounding copy already makes the zone
  # obvious.
  alias Phoenix.LiveView.Rendered

  @formats %{
    date: "%Y-%m-%d",
    long_date: "%B %-d, %Y",
    month_year: "%B %Y",
    long_datetime: "%B %-d, %Y %-I:%M %p",
    short_date: "%b %-d",
    short_datetime: "%b %-d, %-I:%M %p",
    short_datetime_seconds: "%b %-d, %-I:%M:%S %p",
    datetime: "%Y-%m-%d at %-I:%M %p",
    datetime_seconds: "%Y-%m-%d at %-I:%M:%S %p",
    timestamp: "%Y-%m-%d %H:%M:%S",
    short_timestamp: "%Y-%m-%d %H:%M",
    time: "%-I:%M %p",
    time_seconds: "%-I:%M:%S %p",
    # `:log` is finished off by hand in `format/3`; strftime's `%f` prints the
    # microsecond value unpadded, so a timestamp on a whole second would render
    # as ".0" rather than ".000".
    log: "%Y-%m-%d %H:%M:%S",
    # `:log` without the date, under a heading that gives the day.
    log_time: "%H:%M:%S"
  }

  @doc """
  Renders `at` in the viewer's time zone.

  ## Examples

      <.local_datetime at={@firmware.inserted_at} time_zone={@time_zone} />
      <.local_datetime at={cert.not_after} time_zone={@time_zone} format={:date} zone_label={false} />
  """
  attr(:at, :any, required: true, doc: "a `DateTime`, a `NaiveDateTime` assumed to be UTC, or nil")

  attr(:time_zone, :string,
    default: nil,
    doc: "IANA zone name, normally `@time_zone`; unrecognised names fall back to UTC"
  )

  attr(:format, :atom, default: :datetime, values: Map.keys(@formats))

  attr(:zone_label, :boolean,
    default: true,
    doc: "append the zone abbreviation, e.g. `PST`"
  )

  attr(:fallback, :string, default: "", doc: "rendered when `at` is nil")

  attr(:rest, :global)

  @spec local_datetime(map()) :: Rendered.t()
  def local_datetime(assigns) do
    assigns =
      case to_utc(assigns.at) do
        {:ok, utc} ->
          local = DateTime.shift_zone!(utc, Timezone.resolve(assigns.time_zone))

          assign(assigns,
            utc: utc,
            iso: DateTime.to_iso8601(utc),
            utc_title: Calendar.strftime(utc, "%Y-%m-%d %H:%M:%S UTC"),
            text: format(local, assigns.format, assigns.zone_label)
          )

        :error ->
          assign(assigns, utc: nil, iso: nil, utc_title: nil, text: nil)
      end

    ~H"""
    <time :if={@text} datetime={@iso} title={@utc_title} {@rest}>{@text}</time><span :if={is_nil(@text)} {@rest}>{@fallback}</span>
    """
  end

  @doc """
  The zone's current abbreviation, e.g. `PST`.

  For a table of timestamps, label the column once with this rather than
  repeating the zone on every row. It reads as of now, so a table spanning a
  daylight-saving change can hold rows from the neighbouring abbreviation; each
  cell still carries its exact UTC value in a `title`.
  """
  @spec zone_abbr(String.t() | nil) :: String.t()
  def zone_abbr(time_zone) do
    time_zone
    |> Timezone.resolve()
    |> DateTime.now!()
    |> Map.fetch!(:zone_abbr)
  end

  @doc """
  Describes a timestamp relative to now, such as "3 hours ago".

  Anything that is not a `DateTime` or `NaiveDateTime`, such as `nil` for a
  certificate never used, comes back unchanged.
  """
  @spec from_now(term()) :: term()
  def from_now(%DateTime{} = at), do: RelativeTime.from_now(at)
  def from_now(%NaiveDateTime{} = at), do: RelativeTime.from_now(at)
  def from_now(at), do: at

  @doc """
  Formats `at` in `time_zone` as a plain string.

  Prefer `local_datetime/1`; this is for the handful of places that build a
  sentence rather than markup, such as a tooltip body.
  """
  @spec to_local_string(term(), String.t() | nil, atom(), boolean()) :: String.t() | nil
  def to_local_string(at, time_zone, format \\ :datetime, zone_label \\ true) do
    case to_utc(at) do
      {:ok, utc} ->
        utc
        |> DateTime.shift_zone!(Timezone.resolve(time_zone))
        |> format(format, zone_label)

      :error ->
        nil
    end
  end

  @doc """
  The day `at` falls on in the viewer's zone, as a reader would say it:
  "Today", "Yesterday", "Nov 5", or "Nov 5, 2025" for an earlier year.
  """
  @spec day_label(DateTime.t() | NaiveDateTime.t(), String.t() | nil) :: String.t()
  def day_label(at, time_zone) do
    {:ok, utc} = to_utc(at)
    zone = Timezone.resolve(time_zone)
    date = utc |> DateTime.shift_zone!(zone) |> DateTime.to_date()
    today = zone |> DateTime.now!() |> DateTime.to_date()

    case Date.diff(today, date) do
      0 -> "Today"
      1 -> "Yesterday"
      _ when date.year == today.year -> Calendar.strftime(date, "%b %-d")
      _ -> Calendar.strftime(date, "%b %-d, %Y")
    end
  end

  @doc """
  The heading over a day's rows in a list grouped by day: "Today · Nov 6",
  "Yesterday · Nov 5", or `day_label/2` alone for an earlier day.
  """
  @spec day_heading(DateTime.t(), String.t() | nil) :: String.t()
  def day_heading(at, time_zone) do
    case day_label(at, time_zone) do
      relative when relative in ["Today", "Yesterday"] ->
        "#{relative} · #{at |> DateTime.shift_zone!(Timezone.resolve(time_zone)) |> Calendar.strftime("%b %-d")}"

      date ->
        date
    end
  end

  @doc """
  The ISO 8601 date `at` falls on in the viewer's zone. Rows carry it in
  `data-day` for the `LogDayStarts` hook, which compares neighbours to find
  where each day starts.
  """
  @spec day_key(DateTime.t(), String.t() | nil) :: String.t()
  def day_key(at, time_zone) do
    at |> DateTime.shift_zone!(Timezone.resolve(time_zone)) |> DateTime.to_date() |> Date.to_iso8601()
  end

  defp format(local, format, zone_label) when format in [:log, :log_time] do
    {microsecond, _precision} = local.microsecond
    milliseconds = microsecond |> div(1000) |> Integer.to_string() |> String.pad_leading(3, "0")

    local
    |> Calendar.strftime(Map.fetch!(@formats, format))
    |> Kernel.<>("." <> milliseconds)
    |> label(local, zone_label)
  end

  defp format(local, format, zone_label) do
    local
    |> Calendar.strftime(Map.fetch!(@formats, format))
    |> label(local, zone_label)
  end

  defp label(formatted, _local, false), do: formatted
  defp label(formatted, local, true), do: formatted <> " " <> local.zone_abbr

  defp to_utc(%DateTime{} = at), do: {:ok, DateTime.shift_zone!(at, "Etc/UTC")}
  defp to_utc(%NaiveDateTime{} = at), do: {:ok, DateTime.from_naive!(at, "Etc/UTC")}
  defp to_utc(_at), do: :error
end
