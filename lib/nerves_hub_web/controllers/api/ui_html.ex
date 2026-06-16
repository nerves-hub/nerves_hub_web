defmodule NervesHubWeb.API.UIHTML do
  use NervesHubWeb, :html

  def index(assigns) do
    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no" />
        <title>API Documentation {" · #{Application.get_env(:nerves_hub, :web_title_suffix)}"}</title>

        <script src="/assets/js/stoplight.js">
        </script>
        <link rel="stylesheet" href="/assets/js/stoplight.css" />
      </head>
      <body>
        <elements-api
          apiDescriptionUrl="/api/openapi"
          router="hash"
          logo="/images/favicon-96x96.png"
          layout="responsive"
        />
      </body>
    </html>
    """
  end
end
