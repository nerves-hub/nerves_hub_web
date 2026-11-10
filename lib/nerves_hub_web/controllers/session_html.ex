defmodule NervesHubWeb.SessionHTML do
  @moduledoc """
  This module contains pages rendered by SessionController.

  See the `session_html` directory for all templates available.
  """
  use NervesHubWeb, :html

  alias NervesHub.Helpers.RelativeTime

  embed_templates("session_html/*")
end
