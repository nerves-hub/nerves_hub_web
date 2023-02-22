defmodule NervesHubWWWWeb.SessionView do
  use NervesHubWWWWeb, :view
  import NervesHubWWWWeb.LayoutView, only: [permit_uninvited_signups: 0]
end
