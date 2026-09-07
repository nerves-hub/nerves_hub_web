defmodule NervesHub.ErrorReports.Payload do
  @moduledoc """
  Turns one report as a device sends it into the attributes we store.

  Everything arriving here is device input, so nothing raises and nothing
  trusts a shape. A report that cannot be read is rejected and its neighbours in
  the batch are kept — the rule `NervesHub.Devices.LogLine` already follows, and
  the reason a device that gets one report wrong does not lose the rest of the
  second it crashed in.

  ## Caps

  A stacktrace is unbounded and a crash loop is not rate-limited by the size of
  what it says, so every field has a ceiling:

  | Field | Cap |
  | --- | --- |
  | `reason` | #{2_048} bytes |
  | `message` | #{8_192} bytes |
  | `frames` | 30 |
  | `context` | 32 keys, 512 bytes per value |

  When anything is cut, `truncated` is set and `payload_bytes` keeps the
  original size, so the UI can say how much was dropped rather than silently
  showing a fragment. That is the same bargain
  `NervesHub.Devices.DeviceMessages.Payload` makes.

  ## Redaction

  Context values are run through that module's redaction before storage.
  Application code attaches whatever was in scope when it caught an error, and
  what was in scope is sometimes a token.

  ## Device vitals are just context

  Uptime, reboot count and free memory carry no special handling here. They
  arrive in `context` like anything else a device wants to say about itself,
  which is what lets a client with different vitals to report -- free heap,
  signal strength -- send them without a change on this side.
  """

  alias NervesHub.Devices.DeviceMessages.Payload, as: DevicePayload

  @max_reason_bytes 2_048
  @max_message_bytes 8_192
  @max_kind_bytes 128
  @max_frames 30
  @max_frame_field_bytes 512
  @max_context_keys 32
  @max_context_key_bytes 128
  @max_context_value_bytes 512
  @max_fingerprint_bytes 256
  @max_firmware_uuid_bytes 64

  @sources ~w(logger manual)

  @typedoc """
  One frame of a stacktrace, innermost first.

  Every field is optional, because a runtime that cannot supply one is more
  useful reporting the rest than reporting nothing.
  """
  @type frame() :: %{
          module: String.t() | nil,
          function: String.t() | nil,
          file: String.t() | nil,
          line: non_neg_integer() | nil
        }

  @typedoc """
  A report validated, capped and ready to store.

  Atom keys, unlike the string-keyed map that arrived: by this point the shape
  is ours rather than the device's.
  """
  @type attrs() :: %{
          timestamp: DateTime.t(),
          kind: String.t(),
          source: String.t(),
          reason: String.t(),
          message: String.t(),
          frames: [frame()],
          context: %{optional(String.t()) => String.t()},
          fingerprint: String.t() | nil,
          firmware_uuid: String.t(),
          payload_bytes: non_neg_integer(),
          truncated: 0 | 1
        }

  @doc "How many frames one report may carry."
  def max_frames(), do: @max_frames

  @doc """
  Validates and caps one report.

  Returns `{:error, :missing_timestamp | :missing_kind | :missing_reason |
  :malformed}` for anything unusable.
  """
  @spec normalize(term()) :: {:ok, attrs()} | {:error, atom()}
  def normalize(report) when is_map(report) do
    with {:ok, timestamp} <- timestamp(report),
         {:ok, kind} <- required_string(report, "kind", :missing_kind),
         {:ok, reason} <- required_string(report, "reason", :missing_reason) do
      {reason, reason_cut} = cap(reason, @max_reason_bytes)
      {message, message_cut} = cap(string(report["message"], ""), @max_message_bytes)
      {frames, frames_cut} = frames(report["frames"])
      {context, context_cut} = context(report["context"])

      {:ok,
       %{
         timestamp: timestamp,
         kind: elem(cap(kind, @max_kind_bytes), 0),
         source: source(report["source"]),
         reason: reason,
         message: message,
         frames: frames,
         context: context,
         fingerprint: fingerprint(report["fingerprint"]),
         firmware_uuid: elem(cap(string(report["firmware_uuid"], ""), @max_firmware_uuid_bytes), 0),
         payload_bytes: original_size(report),
         truncated: boolean_to_flag(reason_cut or message_cut or frames_cut or context_cut)
       }}
    end
  end

  def normalize(_report), do: {:error, :malformed}

  # ------------------------------------------------------------------ fields

  # Required, and deliberately not defaulted to the time of arrival. A report
  # the server stamps claims the device crashed whenever the network got around
  # to delivering it, which is exactly wrong for a client that buffers across a
  # disconnect and sends the backlog on reconnect.
  defp timestamp(%{"timestamp" => %DateTime{} = timestamp}), do: {:ok, timestamp}

  defp timestamp(%{"timestamp" => timestamp}) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, parsed, _offset} -> {:ok, parsed}
      _ -> {:error, :missing_timestamp}
    end
  end

  # Where every existing client puts it, so the logging extension's shape is
  # accepted here too rather than making clients carry two conventions.
  defp timestamp(%{"meta" => %{"time" => time}}), do: from_microseconds(time)
  defp timestamp(_report), do: {:error, :missing_timestamp}

  defp from_microseconds(time) when is_binary(time) do
    case Integer.parse(time) do
      {micros, ""} -> from_microseconds(micros)
      _ -> {:error, :missing_timestamp}
    end
  end

  defp from_microseconds(time) when is_integer(time) do
    case DateTime.from_unix(time, :microsecond) do
      {:ok, timestamp} -> {:ok, timestamp}
      {:error, _reason} -> {:error, :missing_timestamp}
    end
  end

  defp from_microseconds(_time), do: {:error, :missing_timestamp}

  defp required_string(report, key, error) do
    case string(report[key], "") do
      "" -> {:error, error}
      value -> {:ok, value}
    end
  end

  # Free text, matched literally, so an unknown value is kept rather than
  # rewritten -- but only one of the two known ones is allowed to claim a
  # device asked for it deliberately.
  defp source(source) when source in @sources, do: source
  defp source(_source), do: "logger"

  defp fingerprint(fingerprint) when is_binary(fingerprint) do
    case String.trim(fingerprint) do
      "" -> nil
      trimmed -> elem(cap(trimmed, @max_fingerprint_bytes), 0)
    end
  end

  defp fingerprint(_fingerprint), do: nil

  defp frames(frames) when is_list(frames) do
    {kept, dropped} = Enum.split(frames, @max_frames)

    {Enum.map(kept, &frame/1), dropped != []}
  end

  defp frames(_frames), do: {[], false}

  defp frame(frame) when is_map(frame) do
    %{
      module: frame_field(frame["module"]),
      function: frame_field(frame["function"]),
      file: frame_field(frame["file"]),
      line: line(frame["line"])
    }
  end

  # A frame that is not a map still occupies its position in the stacktrace, so
  # it is kept as an empty slot rather than dropped -- removing it would shift
  # every frame below it and change the fingerprint.
  defp frame(_frame), do: %{module: nil, function: nil, file: nil, line: nil}

  defp frame_field(value) when is_binary(value) do
    case cap(value, @max_frame_field_bytes) do
      {"", _cut} -> nil
      {capped, _cut} -> capped
    end
  end

  defp frame_field(_value), do: nil

  defp line(line) when is_integer(line) and line >= 0, do: line
  defp line(_line), do: nil

  defp context(context) when is_map(context) do
    # Redaction runs over the whole map, not over each value in turn: it decides
    # by key, so a value handed to it on its own is a value it has no reason to
    # touch. It also has to run before truncation, or a token cut down to 512
    # bytes is still most of a token.
    redacted = DevicePayload.redact(context)

    entries = Enum.take(redacted, @max_context_keys)
    dropped_keys = map_size(redacted) > @max_context_keys

    {pairs, value_cut} =
      Enum.map_reduce(entries, false, fn {key, value}, cut ->
        {key, _key_cut} = cap(string(key, ""), @max_context_key_bytes)
        {value, this_cut} = value |> string("") |> cap(@max_context_value_bytes)

        {{key, value}, cut or this_cut}
      end)

    {Map.new(pairs), dropped_keys or value_cut}
  end

  defp context(_context), do: {%{}, false}

  # ----------------------------------------------------------------- helpers

  defp string(value, _default) when is_binary(value), do: value
  defp string(value, _default) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  defp string(value, _default) when is_number(value), do: to_string(value)
  defp string(nil, default), do: default
  defp string(value, _default), do: inspect(value)

  # Cut on a codepoint boundary, not a byte one: `binary_part/3` at an
  # arbitrary offset can split a multi-byte character and leave a binary that
  # is no longer valid UTF-8, which ClickHouse will take and no UI will render.
  defp cap(value, max_bytes) when is_binary(value) do
    if byte_size(value) <= max_bytes do
      {value, false}
    else
      {truncate_utf8(value, max_bytes), true}
    end
  end

  defp truncate_utf8(value, max_bytes) do
    value
    |> binary_part(0, max_bytes)
    |> String.chunk(:valid)
    |> case do
      [valid | _rest] -> valid
      [] -> ""
    end
  end

  # Measured before anything above ran, so the UI can say how much was dropped.
  defp original_size(report) do
    case Jason.encode(report) do
      {:ok, encoded} -> byte_size(encoded)
      {:error, _reason} -> 0
    end
  end

  defp boolean_to_flag(true), do: 1
  defp boolean_to_flag(false), do: 0
end
