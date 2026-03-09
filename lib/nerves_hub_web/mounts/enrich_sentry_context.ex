defmodule NervesHubWeb.Mounts.EnrichSentryContext do
  @moduledoc """
  Add user information to the Sentry context
  """

  def on_mount(_, _, _, socket) do
    with scope when not is_nil(scope) <- socket.assigns.current_scope,
         user when not is_nil(user) <- scope.user do
      context = %{
        id: user.id,
        email: user.email
      }

      context =
        if org = scope.org do
          Map.merge(context, %{org_id: org.id, org_name: org.name, role: scope.role})
        else
          context
        end

      context =
        if product = scope.product do
          Map.merge(context, %{product_id: product.id, product_name: product.name})
        else
          context
        end

      Sentry.Context.set_user_context(context)

      {:cont, socket}
    else
      _ ->
        {:cont, socket}
    end
  end
end
