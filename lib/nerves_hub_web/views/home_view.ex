defmodule NervesHubWeb.HomeView do
  use NervesHubWeb, :view
  import NervesHubWeb.LayoutView, only: [permit_uninvited_signups: 0]
end
