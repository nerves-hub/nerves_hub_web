defmodule NervesHubWeb.NotFoundError do
  defexception message: "not found", plug_status: 404
end

defmodule NervesHubWeb.UnauthorizedError do
  defexception message: "unauthorized", plug_status: 401, required_role: nil
end
