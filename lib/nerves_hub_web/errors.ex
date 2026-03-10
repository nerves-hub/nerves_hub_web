defmodule NervesHubWeb.NotFoundError do
  defexception message: "not found", plug_status: 404
end

defmodule NervesHubWeb.UnauthorizedError do
  defexception message: "unauthorized", plug_status: 401, required_role: nil
end

defmodule NervesHubWeb.InvalidRequestError do
  defexception [:message, plug_status: 400]

  def exception(info: info) do
    %NervesHubWeb.InvalidRequestError{message: "invalid request: #{info}"}
  end
end
