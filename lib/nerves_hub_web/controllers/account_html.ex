defmodule NervesHubWeb.AccountHTML do
  @moduledoc """
  This module contains pages rendered by AccountController.

  See the `account_html` directory for all templates available.
  """
  use NervesHubWeb, :html

  embed_templates("account_html/*")
end
