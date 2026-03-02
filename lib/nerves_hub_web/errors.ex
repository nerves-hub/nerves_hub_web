defmodule NervesHubWeb.NotFoundError do
  defexception message: "not found", plug_status: 404
end

defmodule NervesHubWeb.RequiresGlobalUniqueIdentifiersError do
  defexception message:
                 "global unique device identifiers required, please check PLATFORM_UNIQUE_DEVICE_IDENTIFIERS is set to true",
               plug_status: 404
end

defmodule NervesHubWeb.UnauthorizedError do
  defexception message: "unauthorized", plug_status: 401, required_role: nil
end
