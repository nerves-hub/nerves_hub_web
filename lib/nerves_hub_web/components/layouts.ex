defmodule NervesHubWeb.Layouts do
  use NervesHubWeb, :html

  alias NervesHubWeb.Components.Navigation
  alias Phoenix.LiveView.JS

  embed_templates("layouts/*")
end
