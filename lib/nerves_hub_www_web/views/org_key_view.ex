defmodule NervesHubWWWWeb.OrgKeyView do
  use NervesHubWWWWeb, :view

  def top_level_error_message(%Ecto.Changeset{errors: errors}) do
    if Keyword.has_key?(errors, :firmwares) do
      "Key is in use. You must delete any firmwares signed by the corresponding private key"
    else
      "Oops, something went wrong! Please check the errors below."
    end
  end
end
