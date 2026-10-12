defmodule NervesHubWeb.AuthRequests do
  @moduledoc """
  One API request, authenticated by a person approving it in their browser
  instead of by a token.

  A client with no credentials (the CLI before `nh user auth`, or a device
  being provisioned) describes the API request it wants to make: method, path
  and JSON body. It holds that request open as an event stream and is handed a
  short code. Someone signed in to NervesHub, by any means including Google,
  types the code into `/auth/approve`, sees what is being asked, and approves
  or denies it.

  Approval only establishes who the request runs as. The request is then
  dispatched through the endpoint exactly as if it had arrived with that
  user's token, so the target route does its own authorization and audit
  logging, and the client receives whatever that route answered, a 403
  included. Nothing here decides what a user may do.

  ## No stored state

  The process serving the client's stream *is* the pending request. It
  registers itself in the `"web"` group cluster under its code, so the
  approval page can find it from any web node, and everything about the
  request travels in that registration's metadata. Denial, expiry, the client
  disconnecting, or the node restarting all end the process, which removes the
  registration and with it any way to approve the request. A request can only
  be decided once, because the process unregisters before acting on a
  decision and exits once it has.

  The forwarded response goes straight down the client's stream and is never
  held anywhere, which matters when the route creates a secret.

  ## Phishing

  Someone who gets you to approve their request runs it as you. The code is
  what stands in the way: it is only ever shown on the requester's screen,
  never put in a URL, so a link alone can't get a request approved. The
  approval page shows the method, path and body being approved, and where the
  request came from, so that the person approving can tell.
  """

  alias NervesHub.Accounts.User
  alias NervesHubWeb.Plugs.Attack
  alias Plug.Adapters.Test.Conn

  require Logger

  @group NervesHub.Group
  @cluster "web"
  @key_prefix "auth_request/"

  # Twenty consonants: no vowels, so a code never spells a word, and nothing
  # that reads as a digit. Eight of them is about 34.5 bits, the example in
  # RFC 8628 section 6.1, and they are only guessable through the throttled
  # approval page while a request is open.
  @alphabet ~c"BCDFGHJKLMNPQRSTVWXZ"
  @code_length 8

  @methods ~w(GET POST PUT PATCH DELETE)
  @max_body_bytes 64 * 1024
  @max_note_length 255

  @user_private :nerves_hub_auth_request_user

  @typedoc "What a client asked to have run, and where it asked from."
  @type request() :: %{
          method: String.t(),
          path: String.t(),
          body: map() | nil,
          note: String.t() | nil,
          remote_ip: String.t(),
          user_agent: String.t() | nil,
          expires_at: DateTime.t()
        }

  @typedoc "The forwarded route's response."
  @type response() :: %{status: pos_integer(), content_type: String.t() | nil, body: term()}

  @doc """
  The `conn.private` key the forwarded request carries its user under.

  `NervesHubWeb.API.Plugs.FetchCurrentUser` honours it in place of a token. A
  client can't set `conn.private`, so only `forward/3` can.
  """
  def user_private_key(), do: @user_private

  @doc "How long a request stays open for approval."
  @spec ttl() :: pos_integer()
  def ttl(), do: config(:ttl, to_timeout(minute: 10))

  @doc """
  How often an idle stream sends a comment, so that proxies in front of the
  endpoint don't close it for inactivity.
  """
  @spec heartbeat_interval() :: pos_integer()
  def heartbeat_interval(), do: config(:heartbeat_interval, to_timeout(second: 15))

  @doc """
  Validate what a client asked for and describe it as a request.

  The body is kept as decoded JSON, and is dispatched as JSON. Paths are
  limited to the API, and never to this endpoint itself.
  """
  @spec new(Plug.Conn.t(), map()) :: {:ok, request()} | {:error, String.t()}
  def new(conn, params) do
    with {:ok, method} <- validate_method(params["method"]),
         {:ok, path} <- validate_path(params["path"]),
         {:ok, body} <- validate_body(params["body"]),
         {:ok, note} <- validate_note(params["note"]) do
      {:ok,
       %{
         method: method,
         path: path,
         body: body,
         note: note,
         remote_ip: format_ip(Attack.client_ip(conn)),
         user_agent: conn |> Plug.Conn.get_req_header("user-agent") |> List.first() |> truncate(),
         expires_at: DateTime.add(DateTime.utc_now(), ttl(), :millisecond)
       }}
    end
  end

  defp validate_method(method) when is_binary(method) do
    method = String.upcase(method)

    if method in @methods,
      do: {:ok, method},
      else: {:error, "method must be one of #{Enum.join(@methods, ", ")}"}
  end

  defp validate_method(_), do: {:error, "method is required"}

  # Checked by segment, the way the router will see it: Plug drops empty
  # segments, so "/api//auth_requests" would otherwise slip past a prefix check.
  defp validate_path("/" <> _ = path) do
    segments = path |> URI.parse() |> Map.get(:path, "") |> String.split("/", trim: true)

    cond do
      Enum.any?(segments, &(&1 in [".", ".."])) -> {:error, "path must not contain . or .. segments"}
      match?(["api", "auth_requests" | _], segments) -> {:error, "path must not be an auth request"}
      match?(["api", _ | _], segments) -> {:ok, path}
      true -> {:error, "path must be an API path, starting with /api/"}
    end
  end

  defp validate_path(_), do: {:error, "path is required, starting with /api/"}

  defp validate_body(nil), do: {:ok, nil}

  # Carried in the registration's metadata, which every web node holds a copy
  # of while the request is open.
  defp validate_body(body) when is_map(body) do
    if byte_size(Jason.encode!(body)) <= @max_body_bytes,
      do: {:ok, body},
      else: {:error, "body must be at most #{@max_body_bytes} bytes as JSON"}
  end

  defp validate_body(_), do: {:error, "body must be a JSON object"}

  defp validate_note(nil), do: {:ok, nil}

  defp validate_note(note) when is_binary(note) do
    if String.length(note) <= @max_note_length,
      do: {:ok, note},
      else: {:error, "note must be at most #{@max_note_length} characters"}
  end

  defp validate_note(_), do: {:error, "note must be a string"}

  defp truncate(nil), do: nil
  defp truncate(value), do: String.slice(value, 0, @max_note_length)

  defp format_ip(ip), do: ip |> :inet.ntoa() |> to_string()

  @doc """
  Register the calling process as the holder of `request`, under a fresh code.

  The caller must keep running for as long as the request is open, and is
  sent `{:auth_request_decision, decision, user, reply_to, ref}` when someone
  decides it. Use `reply/3` to answer.
  """
  @spec register(request()) :: {:ok, String.t()}
  def register(request) do
    code = generate_code()

    case Group.register(@group, key(code), request, cluster: @cluster) do
      :ok -> {:ok, code}
      {:error, :taken} -> register(request)
    end
  end

  @doc "Stop accepting decisions for `code`. Called before acting on one."
  @spec unregister(String.t()) :: :ok
  def unregister(code) do
    _ = Group.unregister(@group, key(code), cluster: @cluster)
    :ok
  end

  @doc """
  Find the open request for a code a person typed, ignoring case, spaces and
  dashes.
  """
  @spec lookup(String.t()) :: {:ok, String.t(), pid(), request()} | {:error, :not_found}
  def lookup(code) do
    code = normalize_code(code)

    case code != "" && Group.lookup(@group, key(code), cluster: @cluster) do
      {pid, request} -> {:ok, code, pid, request}
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Approve or deny the request open under `code`, as `user`.

  On approval this waits for the forwarded request to finish, so the page can
  tell the person approving what the route answered.
  """
  @spec decide(String.t(), :approve | :deny, User.t()) ::
          {:ok, {:approved, pos_integer()} | :denied} | {:error, :not_found | :timeout}
  def decide(code, decision, user) when decision in [:approve, :deny] do
    with {:ok, _code, pid, _request} <- lookup(code) do
      ref = Process.monitor(pid)
      send(pid, {:auth_request_decision, decision, user, self(), ref})

      receive do
        {^ref, result} ->
          Process.demonitor(ref, [:flush])
          {:ok, result}

        {:DOWN, ^ref, :process, _pid, _reason} ->
          {:error, :not_found}
      after
        forward_timeout() + to_timeout(second: 5) ->
          Process.demonitor(ref, [:flush])
          {:error, :timeout}
      end
    end
  end

  @doc "Answer the page that sent a decision."
  @spec reply(pid(), reference(), term()) :: :ok
  def reply(reply_to, ref, result) do
    send(reply_to, {ref, result})
    :ok
  end

  @doc """
  Dispatch `request` through the endpoint as `user` and return the response.

  The request is rebuilt on the scheme, host and port the client reached, and
  from its address and forwarding headers, so that the endpoint's plugs see
  the client rather than this node: `Plug.SSL` doesn't redirect it and
  `NervesHubWeb.Plugs.Attack` buckets it by its own address. Its
  `Authorization` and `Cookie` headers are dropped; the user it runs as is set
  in `conn.private`.

  Runs in its own process so the dispatched request's logger metadata and
  process dictionary don't leak into the stream's, and so a crash in the route
  becomes a 500 response rather than a dropped stream.
  """
  @spec forward(request(), User.t(), Plug.Conn.t()) :: response()
  def forward(request, user, %Plug.Conn{} = origin) do
    endpoint = origin.private[:phoenix_endpoint] || NervesHubWeb.Endpoint

    task = Task.async(fn -> dispatch(endpoint, request, user, origin) end)

    case Task.yield(task, forward_timeout()) || Task.shutdown(task) do
      {:ok, response} -> response
      _ -> %{status: 504, content_type: "application/json", body: %{"errors" => %{"detail" => "Request timed out"}}}
    end
  end

  defp dispatch(endpoint, request, user, origin) do
    url = URI.to_string(%URI{scheme: to_string(origin.scheme), host: origin.host, port: origin.port}) <> request.path

    base = %Plug.Conn{
      remote_ip: origin.remote_ip,
      req_headers: forwarded_headers(origin, request)
    }

    conn =
      base
      |> Conn.conn(request.method, url, encode_body(request))
      |> Plug.Conn.put_private(@user_private, user)

    {Conn, %{ref: ref}} = conn.adapter

    try do
      conn = endpoint.call(conn, endpoint.init([]))
      sent_response(ref) || chunked_response(conn)
    catch
      # The endpoint renders an error response before re-raising, so what the
      # client should see has usually been sent already.
      kind, reason ->
        sent_response(ref) || crashed_response(kind, reason, __STACKTRACE__)
    end
  end

  defp crashed_response(kind, reason, stacktrace) do
    Logger.error("Forwarded auth request crashed: " <> Exception.format(kind, reason, stacktrace))
    %{status: 500, content_type: "application/json", body: %{"errors" => %{"detail" => "Internal server error"}}}
  end

  @dropped_headers ~w(authorization cookie content-type content-length accept)

  defp forwarded_headers(origin, request) do
    headers = Enum.reject(origin.req_headers, fn {name, _} -> name in @dropped_headers end)
    headers = [{"accept", "application/json"} | headers]

    if request.body, do: [{"content-type", "application/json"} | headers], else: headers
  end

  defp encode_body(%{body: nil}), do: nil
  defp encode_body(%{body: body}), do: Jason.encode!(body)

  defp sent_response(ref) do
    receive do
      {^ref, {status, headers, body}} -> build_response(status, headers, body)
    after
      0 -> nil
    end
  end

  defp chunked_response(%Plug.Conn{state: :chunked, adapter: {_, %{chunks: chunks}}} = conn),
    do: build_response(conn.status, conn.resp_headers, chunks || "")

  defp chunked_response(_conn), do: nil

  defp build_response(status, headers, body) do
    content_type =
      case List.keyfind(headers, "content-type", 0) do
        {_, value} -> value
        nil -> nil
      end

    %{status: status, content_type: content_type, body: decode_body(content_type, body)}
  end

  defp decode_body(content_type, body) when is_binary(content_type) and body != "" do
    if String.starts_with?(content_type, "application/json") do
      case Jason.decode(body) do
        {:ok, decoded} -> decoded
        {:error, _} -> body
      end
    else
      body
    end
  end

  defp decode_body(_content_type, body), do: body

  defp forward_timeout(), do: config(:forward_timeout, to_timeout(minute: 1))

  @doc "A code as the requester shows it, eg. `WDJB-MJHT`."
  @spec format_code(String.t()) :: String.t()
  def format_code(code) do
    {first, second} = String.split_at(code, div(@code_length, 2))
    first <> "-" <> second
  end

  @doc false
  def normalize_code(code) when is_binary(code) do
    code
    |> String.upcase()
    |> String.replace(~r/[^A-Z]/, "")
  end

  def normalize_code(_), do: ""

  defp generate_code(acc \\ "")

  defp generate_code(acc) when byte_size(acc) == @code_length, do: acc

  # Rejection sampling: 240 is the largest multiple of the alphabet's size
  # below 256, so every letter is equally likely.
  defp generate_code(acc) do
    <<byte>> = :crypto.strong_rand_bytes(1)

    if byte < 240,
      do: generate_code(acc <> <<Enum.at(@alphabet, rem(byte, length(@alphabet)))>>),
      else: generate_code(acc)
  end

  defp key(code), do: @key_prefix <> code

  @doc """
  Emit `[:nerves_hub, :auth_request, event]` and log it.

  The log line is the record of a request going through this flow. The
  forwarded route records its own effects, as the user who approved it.
  """
  @spec track(atom(), request(), map()) :: :ok
  def track(event, request, extra \\ %{}) do
    metadata =
      Map.merge(
        %{method: request.method, path: request.path, remote_ip: request.remote_ip, user_agent: request.user_agent},
        extra
      )

    :telemetry.execute([:nerves_hub, :auth_request, event], %{count: 1}, metadata)

    # In the message as well as the metadata, since the default formatter
    # doesn't print metadata and this line is the record of the request.
    details = for {key, value} <- Map.take(extra, [:user_id, :status]), into: "", do: " #{key}=#{value}"

    Logger.info(
      "Auth request #{event}: #{request.method} #{request.path} from #{request.remote_ip}#{details}",
      Map.to_list(metadata)
    )
  end

  defp config(key, default) do
    :nerves_hub
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key, default)
  end
end
