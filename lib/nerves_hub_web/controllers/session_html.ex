defmodule NervesHubWeb.SessionHTML do
  @moduledoc """
  This module contains pages rendered by SessionController.

  See the `session_html` directory for all templates available.
  """
  use NervesHubWeb, :html

  embed_templates("session_html/*")

  defp confirmation_code_list(code) do
    code
    |> to_string()
    |> String.split("", trim: true)
  end
end
