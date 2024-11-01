defmodule NervesHubWeb.NotFoundError do
  defexception message: "not found", plug_status: 404
end

defmodule NervesHubWeb.Unauthorized do
  defexception message: "forbidden", plug_status: 401
end
