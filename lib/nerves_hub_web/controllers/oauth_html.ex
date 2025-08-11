defmodule NervesHubWeb.OAuthHTML do
  @moduledoc """
  This module contains pages rendered by OAuthController.

  See the `oauth_html` directory for all templates available.
  """
  use NervesHubWeb, :html

  embed_templates("oauth_html/*")
end
