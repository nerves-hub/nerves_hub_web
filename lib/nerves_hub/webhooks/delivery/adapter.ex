defmodule NervesHub.Webhooks.Delivery.Adapter do
  @moduledoc """
  The Req adapter webhook deliveries are sent with: one Mint connection per
  request, to the address `NervesHub.Webhooks.Destination` checked.

  Req's own adapter cannot pin an address cheaply. Doing it means passing
  `connect_options: [hostname: ...]`, and Req starts a separate Finch instance
  for every distinct set of connect options. Each instance is named with a new
  atom and is never stopped, so every host name somebody typed into a webhook
  would cost the node an atom and a supervision tree for the rest of its life.
  A webhook sends to one endpoint at a modest rate, so a fresh connection per
  delivery costs little and leaves nothing behind.

  The address arrives as the request's `:webhook_address` private field. `nil`
  means private destinations are allowed and the host is connected to by name,
  as any HTTP client would.

  Only the status matters, so the response is read up to its headers and the
  connection closed. A receiver cannot make a delivery buffer a body, or hold a
  worker by streaming one.
  """

  @connect_timeout to_timeout(second: 5)
  @receive_timeout to_timeout(second: 15)

  @doc false
  @spec run(Req.Request.t()) :: {Req.Request.t(), Req.Response.t() | Exception.t()}
  def run(%Req.Request{url: uri} = request) do
    deadline = System.monotonic_time(:millisecond) + @receive_timeout
    method = request.method |> Atom.to_string() |> String.upcase()

    with {:ok, conn} <- connect(uri, Req.Request.get_private(request, :webhook_address)),
         {:ok, conn, ref} <- Mint.HTTP.request(conn, method, path(uri), headers(request), request.body),
         {:ok, conn, response} <- receive_response(conn, ref, %{status: nil, headers: []}, deadline) do
      _ = Mint.HTTP.close(conn)

      {request, Req.Response.new(status: response.status, headers: response.headers)}
    else
      {:error, %Mint.TransportError{} = error} ->
        {request, error}

      {:error, %Mint.HTTPError{} = error} ->
        {request, error}

      {:error, conn, error} ->
        _ = Mint.HTTP.close(conn)
        {request, error}
    end
  end

  defp connect(uri, address) do
    scheme = if uri.scheme == "https", do: :https, else: :http
    opts = [mode: :passive, protocols: [:http1]]

    case address do
      nil ->
        Mint.HTTP.connect(scheme, uri.host, uri.port, [transport_opts: [timeout: @connect_timeout]] ++ opts)

      address ->
        # `hostname` keeps the name for SNI, certificate verification and the
        # Host header, while the socket goes to the address that was checked.
        transport_opts = [timeout: @connect_timeout, inet6: tuple_size(address) == 8]
        Mint.HTTP.connect(scheme, address, uri.port, [hostname: uri.host, transport_opts: transport_opts] ++ opts)
    end
  end

  defp path(%URI{path: path, query: query}) do
    path = if path in [nil, ""], do: "/", else: path

    if query, do: path <> "?" <> query, else: path
  end

  defp headers(%Req.Request{headers: headers}) do
    for {name, values} <- headers, value <- values, do: {name, value}
  end

  defp receive_response(conn, ref, response, deadline) do
    timeout = deadline - System.monotonic_time(:millisecond)

    with true <- timeout > 0,
         {:ok, conn, messages} <- Mint.HTTP.recv(conn, 0, timeout) do
      case Enum.reduce(messages, response, &collect(&1, ref, &2)) do
        %{error: error} -> {:error, conn, error}
        %{status: status, done: true} = response when not is_nil(status) -> {:ok, conn, response}
        response -> receive_response(conn, ref, response, deadline)
      end
    else
      false -> {:error, conn, %Mint.TransportError{reason: :timeout}}
      {:error, conn, error, _messages} -> {:error, conn, error}
    end
  end

  # A 1xx is an interim response, such as 103 Early Hints or a 100 Continue
  # nobody asked for, and the real one follows on the same request. Mint
  # reports each as a status and its headers, so both are passed over. 101
  # is the exception: Mint ends the request on it.
  defp collect({:status, ref, status}, ref, response) when status in 100..199 and status != 101,
    do: Map.put(response, :interim, true)

  # The response is complete enough at its headers: the status is all a
  # delivery is judged on, and `Location` is in them for a redirect.
  defp collect({:status, ref, status}, ref, response), do: Map.merge(response, %{status: status, interim: false})

  defp collect({:headers, ref, _headers}, ref, %{interim: true} = response), do: %{response | interim: false}

  defp collect({:headers, ref, headers}, ref, response),
    do: Map.merge(response, %{headers: response.headers ++ headers, done: true})

  defp collect({:error, ref, error}, ref, response), do: Map.put(response, :error, error)
  defp collect(_data_or_done, _ref, response), do: response
end
