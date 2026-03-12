defmodule NervesHubWeb.API.OrgController do
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Accounts
  alias NervesHub.Repo
  alias NervesHubWeb.API.Schemas.OrgSchemas.OrgListResponse

  @valid_includes ~w(products)

  tags(["Organizations"])
  security([%{}, %{"bearer_auth" => []}])

  operation(:index,
    summary: "List all Organizations the authenticated user belongs to",
    parameters: [
      include: [
        in: :query,
        description: "Comma-separated list of associations to include (e.g. \"products\")",
        type: :string,
        required: false
      ]
    ],
    responses: [
      ok: {"Organization list response", "application/json", OrgListResponse}
    ]
  )

  def index(%{assigns: %{current_scope: %{user: user}}} = conn, params) do
    preloads = parse_includes(params)

    orgs =
      user
      |> Accounts.get_user_orgs()
      |> Repo.preload(preloads)

    render(conn, :index, orgs: orgs)
  end

  defp parse_includes(%{"include" => include}) when is_binary(include) do
    include
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 in @valid_includes))
    |> Enum.map(&String.to_existing_atom/1)
  end

  defp parse_includes(_params), do: []
end
