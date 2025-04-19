defmodule NervesHubWeb.PasswordResetHTML do
  @moduledoc """
  This module contains pages rendered by PasswordResetController.

  See the `password_reset_html` directory for all templates available.
  """
  use NervesHubWeb, :html

  embed_templates("password_reset_html/*")
end
