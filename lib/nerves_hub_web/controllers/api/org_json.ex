defmodule NervesHubWeb.API.OrgJSON do
  @moduledoc false

  alias NervesHubWeb.API.ProductJSON

  def index(%{orgs: orgs}) do
    %{data: for(org <- orgs, do: org(org))}
  end

  defp org(org) do
    base = %{
      name: org.name,
      inserted_at: org.inserted_at,
      updated_at: org.updated_at
    }

    maybe_include(base, :products, org)
  end

  defp maybe_include(map, :products, %{products: products}) when is_list(products) do
    Map.put(map, :products, Enum.map(products, &ProductJSON.product/1))
  end

  defp maybe_include(map, _, _), do: map
end
