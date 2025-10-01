defmodule NervesHubWeb.Plugs.FirmwareDownload do
  @moduledoc """
  A slimmed down Plug.Static for serving firmware files.

  Like Plug.Static, it requires two options:

    * `:at` - the request path to reach for firmware files.
      It must be a string.

    * `:from` - the file system path to read firmware files from.
      It can be either: a string containing a file system path, an
      atom representing the application name (where assets will
      be served from `priv/static`), a tuple containing the
      application name and the directory to serve assets from (besides
      `priv/static`), or an MFA tuple.

  The preferred form is to use `:from` with an atom or tuple, since
  it will make your application independent from the starting directory.
  For example, if you pass:

      plug Plug.Static, from: "priv/app/path"

  Plug.Static will be unable to serve assets if you build releases
  or if you change the current directory. Instead do:

      plug Plug.Static, from: {:app_name, "priv/app/path"}

  If a static asset cannot be found, `Plug.Static` simply forwards
  the connection to the rest of the pipeline.

  ## Options

    * `:only` - filters which requests to serve. This is useful to avoid
      file system access on every request when this plug is mounted
      at `"/"`. For example, if `only: ["images", "favicon.ico"]` is
      specified, only files in the "images" directory and the
      "favicon.ico" file will be served by `Plug.Static`.
      Note that `Plug.Static` matches these filters against request
      uri and not against the filesystem. When requesting
      a file with name containing non-ascii or special characters,
      you should use urlencoded form. For example, you should write
      `only: ["file%20name"]` instead of `only: ["file name"]`.
      Defaults to `nil` (no filtering).

    * `:only_matching` - a relaxed version of `:only` that will
      serve any request as long as one of the given values matches the
      given path. For example, `only_matching: ["images", "favicon"]`
      will match any request that starts at "images" or "favicon",
      be it "/images/foo.png", "/images-high/foo.png", "/favicon.ico"
      or "/favicon-high.ico". Such matches are useful when serving
      digested files at the root. Defaults to `nil` (no filtering).

    * `:content_types` - controls custom MIME type mapping.
      It can be a map with filename as key and content type as value to override
      the default type for matching filenames. For example:
      `content_types: %{"apple-app-site-association" => "application/json"}`.
      Alternatively, it can be the value `false` to opt out of setting the header at all. The latter
      can be used to set the header based on custom logic before calling this plug.
      Defaults to an empty map `%{}`.
  """

  @behaviour Plug
  @allowed_methods ~w(GET HEAD)

  import Plug.Conn
  alias Plug.Conn

  # In this module, the `:prim_file` Erlang module along with the `:file_info`
  # record are used instead of the more common and Elixir-y `File` module and
  # `File.Stat` struct, respectively. The reason behind this is performance: all
  # the `File` operations pass through a single process in order to support node
  # operations that we simply don't need when serving assets.

  require Record
  Record.defrecordp(:file_info, Record.extract(:file_info, from_lib: "kernel/include/file.hrl"))

  defmodule InvalidPathError do
    defexception message: "invalid path for static asset", plug_status: 400
  end

  @impl true
  def init(opts) do
    from =
      case Keyword.fetch!(opts, :from) do
        {_, _} = from -> from
        {_, _, _} = from -> from
        from when is_atom(from) -> {from, "priv/static"}
        from when is_binary(from) -> from
        _ -> raise ArgumentError, ":from must be an atom, a binary or a tuple"
      end

    %{
      only_rules: {Keyword.get(opts, :only, []), Keyword.get(opts, :only_matching, []), :forbidden},
      content_types: Keyword.get(opts, :content_types, %{}),
      from: from,
      at: opts |> Keyword.fetch!(:at) |> Plug.Router.Utils.split()
    }
  end

  @impl true
  def call(%Conn{method: meth} = conn, %{at: at, only_rules: only_rules, from: from} = options)
      when meth in @allowed_methods do
    segments = subset(at, conn.path_info)

    case path_status(only_rules, segments) do
      :forbidden ->
        conn

      _status ->
        segments = Enum.map(segments, &URI.decode/1)

        if invalid_path?(segments) do
          raise InvalidPathError, "invalid path for static asset: #{conn.request_path}"
        end

        range = get_req_header(conn, "range")

        path = path(from, segments)

        case regular_file_info(path) do
          nil -> conn
          file_info -> serve_static({nil, file_info, path}, conn, segments, range, options)
        end
    end
  end

  def call(conn, _options) do
    conn
  end

  defp path_status(_only_rules, []), do: :forbidden
  defp path_status({[], [], _}, _list), do: :allowed

  defp path_status({full, prefix, status}, [h | _]) do
    if h in full or (prefix != [] and match?({0, _}, :binary.match(h, prefix))) do
      :allowed
    else
      status
    end
  end

  defp maybe_put_content_type(conn, false, _), do: conn

  defp maybe_put_content_type(conn, types, filename) do
    content_type = Map.get(types, filename) || MIME.from_path(filename)
    put_resp_header(conn, "content-type", content_type)
  end

  defp serve_static({content_encoding, file_info, path}, conn, segments, range, options) do
    %{
      content_types: types
    } = options

    filename = List.last(segments)

    conn
    |> maybe_put_content_type(types, filename)
    |> put_resp_header("accept-ranges", "bytes")
    |> maybe_add_encoding(content_encoding)
    |> serve_range(file_info, path, range, options)
  end

  defp serve_range(conn, file_info, path, [range], options) do
    file_info(size: file_size) = file_info

    with %{"bytes" => bytes} <- Plug.Conn.Utils.params(range),
         {range_start, range_end} <- start_and_end(bytes, file_size) do
      send_range(conn, path, range_start, range_end, file_size, options)
    else
      _ -> send_entire_file(conn, path, options)
    end
  end

  defp serve_range(conn, _file_info, path, _range, options) do
    send_entire_file(conn, path, options)
  end

  defp start_and_end("-" <> rest, file_size) do
    case Integer.parse(rest) do
      {last, ""} when last > 0 and last <= file_size -> {file_size - last, file_size - 1}
      _ -> :error
    end
  end

  defp start_and_end(range, file_size) do
    case Integer.parse(range) do
      {first, "-"} when first >= 0 ->
        {first, file_size - 1}

      {first, "-" <> rest} when first >= 0 ->
        case Integer.parse(rest) do
          {last, ""} when last >= first -> {first, min(last, file_size - 1)}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp send_range(conn, path, 0, range_end, file_size, options) when range_end == file_size - 1 do
    send_entire_file(conn, path, options)
  end

  defp send_range(conn, path, range_start, range_end, file_size, _options) do
    length = range_end - range_start + 1

    conn
    |> put_resp_header("content-range", "bytes #{range_start}-#{range_end}/#{file_size}")
    |> send_file(206, path, range_start, length)
    |> halt()
  end

  defp send_entire_file(conn, path, _options) do
    conn
    |> send_file(200, path)
    |> halt()
  end

  defp maybe_add_encoding(conn, nil), do: conn
  defp maybe_add_encoding(conn, ce), do: put_resp_header(conn, "content-encoding", ce)

  defp regular_file_info(path) do
    case :prim_file.read_file_info(path) do
      {:ok, file_info(type: :regular) = file_info} ->
        file_info

      _ ->
        nil
    end
  end

  defp path({module, function, arguments}, segments) when is_atom(module) and is_atom(function) and is_list(arguments),
    do: Enum.join([apply(module, function, arguments) | segments], "/")

  defp path({app, from}, segments) when is_atom(app) and is_binary(from),
    do: Enum.join([Application.app_dir(app), from | segments], "/")

  defp path(from, segments), do: Enum.join([from | segments], "/")

  defp subset([h | expected], [h | actual]), do: subset(expected, actual)
  defp subset([], actual), do: actual
  defp subset(_, _), do: []

  defp invalid_path?(list) do
    invalid_path?(list, :binary.compile_pattern(["/", "\\", ":", "\0"]))
  end

  defp invalid_path?([h | _], _match) when h in [".", "..", ""], do: true
  defp invalid_path?([h | t], match), do: String.contains?(h, match) or invalid_path?(t)
  defp invalid_path?([], _match), do: false
end
