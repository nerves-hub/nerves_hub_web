defmodule NervesHubWeb.API.AuthRequestController do
  @moduledoc """
  Holds an auth request open as a server-sent event stream until someone
  approves or denies it, then forwards it and streams back the response.

  See `NervesHubWeb.AuthRequests` for how the flow works. The stream carries
  these events, each with a JSON `data` line:

    * `pending` - `code`, `verification_uri` and `expires_in` (seconds). Show
      the code and the URL to whoever will approve the request.
    * `approved` - `user`, with the `name` and `email` the request will run as.
    * `response` - `status`, `content_type` and `body` of the forwarded
      request's response. `body` is decoded when it is JSON.
    * `denied` or `expired` - the request was not run.

  Comment lines (starting with `:`) are sent while idle and carry nothing.
  The stream ends after `response`, `denied` or `expired`. If it drops before
  then, the request is abandoned and has to be made again.
  """

  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHubWeb.API.Schemas.AuthRequestRequest
  alias NervesHubWeb.API.Schemas.ErrorSchemas
  alias NervesHubWeb.AuthRequests
  alias NervesHubWeb.Plugs.Attack

  plug(Attack)

  tags(["Auth"])

  operation(:create,
    summary: "Make one API request, approved by a user in their browser",
    description: """
    For clients without a token. Describe an API request, then show the `code` from the
    `pending` event to someone signed in to NervesHub, who approves it at the `verification_uri`.
    The request then runs as them and its response is sent as the `response` event.
    The stream stays open until then, or until the request expires.
    """,
    request_body: {"The API request to make", "application/json", AuthRequestRequest, required: true},
    responses: [
      ok: {"Server-sent events, as described above", "text/event-stream", %OpenApiSpex.Schema{type: :string}},
      unprocessable_entity: {"Invalid request", "application/json", ErrorSchemas.ErrorResponse}
    ],
    security: []
  )

  def create(conn, params) do
    case AuthRequests.new(conn, params) do
      {:ok, request} ->
        {:ok, code} = AuthRequests.register(request)
        AuthRequests.track(:start, request)

        conn =
          conn
          |> put_resp_content_type("text/event-stream")
          |> put_resp_header("cache-control", "no-cache")
          # nginx buffers responses by default, which would hold every event
          # back until the stream ended.
          |> put_resp_header("x-accel-buffering", "no")
          |> send_chunked(200)

        pending = %{
          code: AuthRequests.format_code(code),
          verification_uri: url(conn, ~p"/auth/approve"),
          expires_in: div(AuthRequests.ttl(), 1000)
        }

        case send_event(conn, "pending", pending) do
          {:ok, conn} ->
            deadline = System.monotonic_time(:millisecond) + AuthRequests.ttl()
            wait(conn, code, request, deadline)

          {:error, _} ->
            AuthRequests.track(:closed, request)
            conn
        end

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{detail: reason}})
    end
  end

  defp wait(conn, code, request, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    receive do
      {:auth_request_decision, :approve, user, reply_to, ref} ->
        :ok = AuthRequests.unregister(code)
        AuthRequests.track(:approved, request, %{user_id: user.id})

        conn = emit(conn, "approved", %{user: %{name: user.name, email: user.email}})
        response = AuthRequests.forward(request, user, conn)
        AuthRequests.reply(reply_to, ref, {:approved, response.status})
        AuthRequests.track(:completed, request, %{user_id: user.id, status: response.status})

        emit(conn, "response", response)

      {:auth_request_decision, :deny, user, reply_to, ref} ->
        :ok = AuthRequests.unregister(code)
        AuthRequests.reply(reply_to, ref, :denied)
        AuthRequests.track(:denied, request, %{user_id: user.id})

        emit(conn, "denied", %{})
    after
      max(min(AuthRequests.heartbeat_interval(), remaining), 0) ->
        if remaining <= 0 do
          :ok = AuthRequests.unregister(code)
          AuthRequests.track(:expired, request)
          emit(conn, "expired", %{})
        else
          heartbeat(conn, code, request, deadline)
        end
    end
  end

  defp heartbeat(conn, code, request, deadline) do
    case chunk(conn, ": keepalive\n\n") do
      {:ok, conn} ->
        wait(conn, code, request, deadline)

      {:error, _} ->
        # The client went away. Leaving the process unregisters the code.
        AuthRequests.track(:closed, request)
        conn
    end
  end

  # Once a request is decided there is nothing more to do if the client has
  # gone, so a failed write is only the end of the stream.
  defp emit(conn, event, data) do
    case send_event(conn, event, data) do
      {:ok, conn} -> conn
      {:error, _} -> conn
    end
  end

  defp send_event(conn, event, data) do
    chunk(conn, "event: #{event}\ndata: #{Jason.encode!(data)}\n\n")
  end
end
