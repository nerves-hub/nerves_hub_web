defmodule NervesHubWeb.NotFoundError do
  defexception message: "not found", plug_status: 404
end

defmodule NervesHubWeb.SentryEventFilter do
  def filter_non_500(%Sentry.Event{original_exception: exception} = event) do
    cond do
      Plug.Exception.status(exception) < 500 ->
        false

      # Fall back to the default event filter.
      Sentry.DefaultEventFilter.exclude_exception?(exception, event.source) ->
        false

      true ->
        event
    end
  end
end
