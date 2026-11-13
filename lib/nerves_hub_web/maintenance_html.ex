defmodule NervesHubWeb.MaintenanceHTML do
  @moduledoc """
  The page shown while `MAINTENANCE_MODE` is set.

  It carries its own styles and artwork instead of using the app's layouts and
  assets, so that it depends on nothing else being up.
  """

  use Phoenix.Component

  embed_templates("maintenance_html/*")
end
