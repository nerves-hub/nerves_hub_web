defmodule NervesHubWeb.Live.Account.SlackLink do
  @moduledoc """
  Where a person links their Slack account to their NervesHub account, by
  signing in with Slack (`NervesHub.Integrations.Slack.Users`). They arrive from the link
  NervesHub shows them in Slack the first time they click one of its buttons.
  """
  use NervesHubWeb, :live_view

  alias NervesHub.Branding

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    socket
    |> page_title("Link Slack")
    |> assign(:team, params["team"])
    |> ok()
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <NervesHubWeb.Layouts.no_sidebar flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto flex w-full max-w-xl flex-col gap-6 p-6">
        <div id="slack-link" class="flex flex-col gap-4 rounded border border-base-700 bg-surface-raised p-6 text-sm text-base-300">
          <h1 class="text-lg font-semibold text-base-50">Link your Slack account</h1>
          <p>
            Sign in with Slack as yourself to link your Slack account to <strong class="text-base-50">{@current_scope.user.email}</strong>.
            What you then do with {Branding.friendly_platform_name()}'s buttons in Slack is done as you, with your permissions in each organization.
          </p>
          <p>Slack, not this page, decides which Slack account is linked: the one you sign in with.</p>
          <.form for={%{}} action={~p"/integrations/slack/link/start"} method="post">
            <input :if={@team} type="hidden" name="team" value={@team} />
            <.button style="primary" type="submit">Sign in with Slack</.button>
          </.form>
        </div>
      </div>
    </NervesHubWeb.Layouts.no_sidebar>
    """
  end
end
