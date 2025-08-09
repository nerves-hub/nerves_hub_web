defmodule NervesHubWeb.MFAHTML do
  @moduledoc """
  This module contains pages rendered by MFAController.

  See the `mfa_html` directory for all templates available.
  """
  use NervesHubWeb, :html

  embed_templates("mfa_html/*")
end
