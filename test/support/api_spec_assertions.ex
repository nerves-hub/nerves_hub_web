defmodule NervesHubWeb.APISpecAssertions do
  @moduledoc """
  Checks a real API response against the OpenAPI spec published at
  `/api/openapi`, so the two can't drift apart unnoticed.

  `assert_documented_response/2` finds the operation the request was routed to,
  then checks that:

    * the status code is one the operation documents,
    * a documented body was sent, or no body when none is documented,
    * the body conforms to the documented schema, and
    * every field sent is documented, and every documented field is sent.

  The last check is stricter than the schema alone, which lets undocumented
  fields through and doesn't notice documented ones that never arrive. A field
  that is only sent some of the time is named in `:absent` as a path, such as
  `"data.shared_secret"`, with `[]` for the items of an array
  (`"data[].created_by"`).
  """

  import ExUnit.Assertions

  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema
  alias OpenApiSpex.TestAssertions

  @doc """
  The API spec, built once per test run.
  """
  def spec() do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        spec = NervesHubWeb.ApiSpec.spec()
        :persistent_term.put(__MODULE__, spec)
        spec

      spec ->
        spec
    end
  end

  @doc """
  The spec's form of a router path: `/api/devices/:identifier` becomes
  `/api/devices/{identifier}`.
  """
  def spec_path(route), do: Regex.replace(~r/:(\w+)/, route, "{\\1}")

  @doc """
  Assert that `conn`'s response is the one the spec documents for its route.
  Returns `conn`.
  """
  def assert_documented_response(%Plug.Conn{} = conn, opts \\ []) do
    spec = spec()
    operation = operation_for!(spec, conn)
    path = "#{conn.method} #{conn.request_path}"

    response =
      Map.get(operation.responses, conn.status) ||
        flunk(
          "#{path} (#{operation.operationId}) returned #{conn.status}, but the spec documents only " <>
            (operation.responses |> Map.keys() |> Enum.sort() |> inspect())
        )

    case response_schema(response, spec) do
      nil ->
        assert conn.resp_body == "",
               "#{path} returned a body for #{conn.status}, but the spec documents none: #{conn.resp_body}"

      schema ->
        body = Jason.decode!(conn.resp_body)
        TestAssertions.assert_raw_schema(body, schema, spec)
        assert_same_fields(body, schema, spec, "", Keyword.get(opts, :absent, []))
    end

    conn
  end

  defp operation_for!(spec, conn) do
    route =
      case Phoenix.Router.route_info(NervesHubWeb.Router, conn.method, conn.request_path, conn.host) do
        %{route: route} -> route
        :error -> flunk("#{conn.method} #{conn.request_path} matches no route")
      end

    path_item = Map.get(spec.paths, spec_path(route)) || flunk("The spec has no path for #{route}")
    verb = conn.method |> String.downcase() |> String.to_existing_atom()

    Map.get(path_item, verb) || flunk("The spec documents no #{conn.method} for #{spec_path(route)}")
  end

  defp response_schema(%Reference{} = ref, spec),
    do: ref |> Reference.resolve_response(spec.components.responses) |> response_schema(spec)

  defp response_schema(%{content: %{"application/json" => %{schema: schema}}}, _spec), do: schema
  defp response_schema(%{content: content}, _spec) when content in [nil, %{}], do: nil

  defp assert_same_fields(nil, _schema, _spec, _path, _absent), do: :ok

  defp assert_same_fields(value, schema, spec, path, absent) do
    case resolve(schema, spec) do
      %Schema{allOf: [_ | _]} = all_of ->
        assert_object_fields(value, all_properties(all_of, spec), spec, path, absent)

      %Schema{type: :object, properties: %{} = properties} when map_size(properties) > 0 ->
        assert_object_fields(value, properties, spec, path, absent)

      %Schema{type: :array, items: items} when is_list(value) and not is_nil(items) ->
        Enum.each(value, &assert_same_fields(&1, items, spec, path <> "[]", absent))

      # A oneOf or anyOf names no single set of fields, and a free-form object
      # has none to compare.
      _ ->
        :ok
    end
  end

  defp assert_object_fields(value, properties, spec, path, absent) when is_map(value) do
    documented = properties |> Map.keys() |> MapSet.new(&to_string/1)
    sent = value |> Map.keys() |> MapSet.new()
    allowed_absent = MapSet.new(absent)

    undocumented = MapSet.difference(sent, documented)
    assert MapSet.size(undocumented) == 0, "#{at(path)} sends fields the spec doesn't document: #{list(undocumented)}"

    unsent =
      documented
      |> MapSet.difference(sent)
      |> Enum.reject(&MapSet.member?(allowed_absent, join(path, &1)))

    assert unsent == [], "#{at(path)} doesn't send fields the spec documents: #{Enum.join(unsent, ", ")}"

    for {name, property} <- properties, Map.has_key?(value, to_string(name)) do
      assert_same_fields(value[to_string(name)], property, spec, join(path, to_string(name)), absent)
    end

    :ok
  end

  defp assert_object_fields(value, _properties, _spec, path, _absent),
    do: flunk("#{at(path)} is documented as an object, but was #{inspect(value)}")

  # The properties of an `allOf` are those of every schema in it, however deeply
  # they nest.
  defp all_properties(schema, spec) do
    case resolve(schema, spec) do
      %Schema{allOf: [_ | _] = parts} ->
        parts |> Enum.map(&all_properties(&1, spec)) |> Enum.reduce(%{}, &Map.merge(&2, &1))

      %Schema{properties: properties} ->
        properties || %{}
    end
  end

  defp resolve(%Reference{} = ref, spec), do: Reference.resolve_schema(ref, spec.components.schemas)
  defp resolve(module, _spec) when is_atom(module), do: module.schema()
  defp resolve(schema, _spec), do: schema

  defp join("", name), do: name
  defp join(path, name), do: "#{path}.#{name}"

  defp at(""), do: "The body"
  defp at(path), do: "`#{path}`"

  defp list(set), do: set |> Enum.sort() |> Enum.join(", ")
end
