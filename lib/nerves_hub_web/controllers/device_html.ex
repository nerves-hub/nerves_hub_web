defmodule NervesHubWeb.DeviceHTML do
  @moduledoc """
  This module contains pages rendered by DeviceController.

  See the `device_html` directory for all templates available.
  """
  use NervesHubWeb, :html

  embed_templates("device_html/*")
end
