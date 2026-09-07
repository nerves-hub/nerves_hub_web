defmodule NervesHub.ManagedDeployments.WorkflowValidator do
  @moduledoc """
  Checks an uploaded workflow definition against the JSON schema.

  Definitions are written by hand, so the useful thing is to say what is wrong
  and where, the way a CI config would. Errors read as
  `steps/1/concurrent_updates: Type mismatch. Expected Integer but got String.`

  The schema is read at compile time. It sits next to this module rather than in
  `priv/`, and only compiled files travel into a release, so reading it at
  runtime would work in development and fail once deployed.
  """

  @schema_path Path.join(__DIR__, "workflow-definition.schema.json")
  @external_resource @schema_path

  @schema @schema_path |> File.read!() |> JSON.decode!() |> ExJsonSchema.Schema.resolve()

  @doc """
  Validate a decoded workflow definition.

  Returns every problem rather than the first, so a definition can be fixed in
  one pass.
  """
  @spec validate(term()) :: :ok | {:error, [String.t()]}
  def validate(definition) when is_map(definition) do
    case ExJsonSchema.Validator.validate(@schema, definition) do
      :ok -> :ok
      {:error, errors} -> {:error, Enum.map(errors, &describe/1)}
    end
  end

  def validate(_definition), do: {:error, ["The workflow definition must be a JSON object."]}

  # The library reports a JSON pointer; "#/steps/1/name" reads better to someone
  # editing the file as "steps/1/name".
  defp describe({message, "#" <> path}) when path not in ["", "/"] do
    "#{String.trim_leading(path, "/")}: #{message}"
  end

  defp describe({message, _root}), do: message
end
