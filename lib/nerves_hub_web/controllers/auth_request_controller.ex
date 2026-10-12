defmodule NervesHubWeb.AuthRequestController do
  @moduledoc """
  Where a signed in user approves or denies an auth request, by typing the code
  the requester is showing.

  See `NervesHubWeb.AuthRequests`.
  """

  use NervesHubWeb, :controller

  alias NervesHubWeb.AuthRequests
  alias NervesHubWeb.Plugs.Attack

  # Codes are only guessable here, and only while a request is open.
  plug(Attack when action in [:show, :decide])

  def new(conn, _params) do
    render(conn, :new, page_title: "Approve a request", error: nil)
  end

  def show(conn, %{"code" => code}) do
    case AuthRequests.lookup(code) do
      {:ok, code, _pid, request} ->
        render(conn, :show,
          page_title: "Approve a request",
          code: AuthRequests.format_code(code),
          request: request
        )

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> render(:new, page_title: "Approve a request", error: not_found_message())
    end
  end

  def show(conn, _params), do: redirect(conn, to: ~p"/auth/approve")

  def decide(conn, %{"code" => code, "decision" => decision}) when decision in ["approve", "deny"] do
    user = conn.assigns.current_scope.user

    case AuthRequests.decide(code, String.to_existing_atom(decision), user) do
      {:ok, result} ->
        render(conn, :decided, page_title: "Approve a request", result: result)

      {:error, :timeout} ->
        render(conn, :decided, page_title: "Approve a request", result: :timeout)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> render(:new, page_title: "Approve a request", error: not_found_message())
    end
  end

  def decide(conn, _params), do: redirect(conn, to: ~p"/auth/approve")

  defp not_found_message() do
    "There is no open request with that code. It may have expired, been decided already, " <>
      "or been cancelled by whoever made it."
  end
end
