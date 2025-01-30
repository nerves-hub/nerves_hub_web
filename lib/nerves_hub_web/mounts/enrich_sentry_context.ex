defmodule NervesHubWeb.Mounts.EnrichSentryContext do
  @moduledoc """
  Add user information to the Sentry context
  """

  def on_mount(_, _, _, socket) do
    if user = socket.assigns.user do
      Sentry.Context.set_user_context(%{
        id: user.id,
        email: user.email
      })

      {:cont, socket}
    else
      {:cont, socket}
    end
  end
end
