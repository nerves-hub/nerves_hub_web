defmodule NervesHubWeb.API.ChangesetJSON do
  @moduledoc false

  def error(%{message: message}) do
    # For cases where the error is related to a validation, but its done a little
    # differently, eg. NervesHubWeb.API.DeploymentGroupController.create/2
    %{errors: %{detail: message}}
  end

  def error(%{changeset: changeset}) do
    # When encoded, the changeset returns its errors
    # as a JSON object. So we just pass it forward.
    %{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)}
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end
end
