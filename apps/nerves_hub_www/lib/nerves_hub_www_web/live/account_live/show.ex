defmodule NervesHubWWWWeb.AccountLive.Show do
  use NervesHubWWWWeb, :live_view

  alias NervesHubWWWWeb.LayoutView.DateTimeFormat, as: DateTimeFormat

  alias NervesHubWebCore.{Accounts, Accounts.UserToken, Repo}

  def render(%{live_action: :new_token} = assigns) do
    ~H"""
    <.form let={f} for={@changeset} class="form-group" phx-submit="save-token">
      <label for="note_input">Note</label>
      <%= text_input f, :note, class: "form-control" %>
      <div class="has-error"><%= error_tag f, :note %></div>
      <div class="button-submit-wrapper">
        <button class="btn btn-secondary" phx-click="cancel">Cancel</button>
        <%= submit "Generate", class: "btn btn-primary" %>
      </div>
    </.form>
    """
  end

  def render(%{tab: "tokens"} = assigns) do
    ~H"""
    <div class="action-row">
      <div class="flex-row align-items-center">
        <h1 class="mr-3 mb-0">User Access Tokens</h1>
      </div>
      <div>
        <a class="btn btn-outline-light btn-action" aria-label="Generate new token" phx-click="new-token">
          <div class="button-icon add"></div>
          <span class="action-text">Generate new token</span>
        </a>
      </div>
    </div>
    <%= if err = live_flash(@flash, :error) do %>
      <div class="alert alert-danger alert-dismissible">
        <button type="button" class="btn-close" data-bs-dismiss="alert">&times;</button>
        <%= err %>
      </div>
    <% end %>

    <%= if info = live_flash(@flash, :info) do %>
      <div class="alert alert-info alert-dismissible">
        <button type="button" class="btn-close" data-bs-dismiss="alert">&times;</button>
        <%= info %>
      </div>
    <% end %>
    <table id="user_tokens" class="table table-sm table-hover">
      <thead>
        <tr>
          <th>Note</th>
          <th>Token</th>
          <th>Last Used</th>
          <th></th>
        </tr>
      </thead>
      <%= for token <- @user.user_tokens do %>
        <tr class="item">
          <td>
            <div class="mobile-label help-text">Note</div>
            <code class="color-white wb-ba"><%= token.note %></code>
          </td>
          <td>
            <div class="mobile-label help-text">Token</div>
            ****<%= elem(String.split_at(token.token, -4), 1) %>
          </td>
          <td title={token.last_used}>
            <div class="mobile-label help-text">Last used</div>
            <%= if !is_nil(token.last_used) do %>
              <%= DateTimeFormat.from_now(token.last_used) %>
            <% else %>
              <span class="text-muted">Never</span>
            <% end %>
          </td>
          <td class="actions">
            <div class="mobile-label help-text">Actions</div>
            <div class="dropdown options">
              <a class="dropdown-toggle options" href="#" id={to_string(token.id)} data-bs-toggle="dropdown" aria-haspopup="true" aria-expanded="false">
                <div class="mobile-label pr-2">Open</div>
                <img src="/images/icons/more.svg" alt="options" />
              </a>
              <div class="dropdown-menu dropdown-menu-right">
              <button class="dropdown-item" type="button" phx-click="delete-token" phx-value-token-id={token.id} data-confirm="Are you sure?">
                <span>Delete</span>
              </button>
              </div>
            </div>
          </td>
        </tr>
      <% end %>
    </table>
    """
  end

  def render(assigns) do
    ~H"""
    """
  end

  def mount(_params, %{"auth_user_id" => user_id} = params, socket) do
    socket =
      socket
      |> assign_new(:user, fn -> Accounts.get_user!(user_id) end)
      |> update(:user, &Repo.preload(&1, [:user_tokens]))
      |> assign(:tab, params["tab"])

    {:ok, socket}
  rescue
    e ->
      socket_error(socket, live_view_error(e))
  end

  # Catch-all to handle when LV sessions change.
  # Typically this is after a deploy when the
  # session structure in the module has changed
  # for mount/3
  def mount(_, _, socket) do
    socket_error(socket, live_view_error(:update))
  end

  def handle_event("new-token", _params, socket) do
    changeset = UserToken.create_changeset(socket.assigns.user, %{})
    {:noreply, assign(socket, live_action: :new_token, changeset: changeset)}
  end

  def handle_event(
        "save-token",
        %{"user_token" => %{"note" => note}},
        %{assigns: %{user: user}} = socket
      ) do
    socket =
      case Accounts.create_user_token(user, note) do
        {:ok, %{token: token} = ut} ->
          assign(socket,
            live_action: nil,
            changeset: nil,
            user: update_in(user.user_tokens, &[ut | &1])
          )
          |> put_flash(:info, "Token Created: #{token}")

        {:error, c} ->
          assign(socket, changeset: c)
      end

    {:noreply, socket}
  end

  def handle_event(
        "delete-token",
        %{"token-id" => id_str},
        %{assigns: %{user: %{user_tokens: tokens} = user}} = socket
      ) do
    id = String.to_integer(id_str)
    target = Enum.find(tokens, &(&1.id == id))

    socket =
      case Repo.delete(target) do
        {:ok, _} ->
          filtered = Enum.reject(tokens, &(&1.id == id))

          assign(socket, user: %{user | user_tokens: filtered})
          |> put_flash(:info, "Token deleted")

        _ ->
          put_flash(socket, :error, "Could not delete token")
      end

    {:noreply, socket}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, assign(socket, live_action: nil)}
  end
end
