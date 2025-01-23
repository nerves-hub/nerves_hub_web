defmodule NervesHubWeb.Components.Icons do
  use Phoenix.Component

  @doc """
  A little icon helper.

  ## Examples

      <.icon name="save" />
      <.icon name="trash" class="ml-1 w-3 h-3" />
  """
  attr(:name, :string, required: true)
  attr(:class, :string, default: nil)

  def icon(%{name: "save"} = assigns) do
    ~H"""
    <svg class={["size-5", @class]} viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path
        d="M6.66671 16.6667H5.00004C4.07957 16.6667 3.33337 15.9205 3.33337 15V5.00004C3.33337 4.07957 4.07957 3.33337 5.00004 3.33337H12.643C13.085 3.33337 13.509 3.50897 13.8215 3.82153L16.1786 6.17855C16.4911 6.49111 16.6667 6.91504 16.6667 7.35706V15C16.6667 15.9205 15.9205 16.6667 15 16.6667H13.3334M6.66671 16.6667V12.5H13.3334V16.6667M6.66671 16.6667H13.3334M6.66671 6.66671V9.16671H9.16671V6.66671H6.66671Z"
        stroke-width="1.2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  def icon(%{name: "export"} = assigns) do
    ~H"""
    <svg class={["size-5", @class]} viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path
        d="M10.0002 3.33325L6.66683 6.66659M10.0002 3.33325L13.3335 6.66659M10.0002 3.33325L10.0002 13.3333M3.3335 16.6666L16.6668 16.6666"
        stroke-width="1.2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  def icon(%{name: "add"} = assigns) do
    ~H"""
    <svg class={["size-5", @class]} viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M4.1665 10.0001H9.99984M15.8332 10.0001H9.99984M9.99984 10.0001V4.16675M9.99984 10.0001V15.8334" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round" />
    </svg>
    """
  end

  def icon(%{name: "filter"} = assigns) do
    ~H"""
    <svg class={["size-5", @class]} viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path
        d="M15.0002 3.33325H5.00022C4.07974 3.33325 3.31217 4.09102 3.53926 4.98304C4.03025 6.91168 5.36208 8.50445 7.12143 9.34803C7.80715 9.67683 8.33355 10.3214 8.33355 11.0819V16.1516C8.33355 16.771 8.98548 17.174 9.53956 16.8969L11.2062 16.0636C11.4886 15.9224 11.6669 15.6339 11.6669 15.3182V11.0819C11.6669 10.3214 12.1933 9.67683 12.879 9.34803C14.6384 8.50445 15.9702 6.91168 16.4612 4.98304C16.6883 4.09102 15.9207 3.33325 15.0002 3.33325Z"
        stroke-width="1.2"
      />
    </svg>
    """
  end

  def icon(%{name: "power"} = assigns) do
    ~H"""
    <svg class={["size-5", @class]} viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path
        d="M14.4097 4.99992C15.7938 6.22149 16.6667 8.00876 16.6667 9.99992C16.6667 13.6818 13.6819 16.6666 10 16.6666C6.31814 16.6666 3.33337 13.6818 3.33337 9.99992C3.33337 8.00876 4.2063 6.22149 5.59033 4.99992M10 9.99992V3.33325"
        stroke-width="1.2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  def icon(%{name: "download"} = assigns) do
    ~H"""
    <svg class={["size-5", @class]} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path
        d="M18 21L15 18M18 21L21 18M18 21V15M20 9V8.82843C20 8.29799 19.7893 7.78929 19.4142 7.41421L15.5858 3.58579C15.2107 3.21071 14.702 3 14.1716 3H14M20 9H16C14.8954 9 14 8.10457 14 7V3M20 9V11M14 3H6C4.89543 3 4 3.89543 4 5V19C4 20.1046 4.89543 21 6 21H12"
        stroke-width="1.2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  def icon(%{name: "connection"} = assigns) do
    ~H"""
    <svg class={["size-5", @class]} viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path
        d="M13.5714 11.4644C12.6574 10.5596 11.3947 9.99992 9.99996 9.99992C8.60523 9.99992 7.34254 10.5596 6.42853 11.4644M15.9523 9.10736C14.429 7.59933 12.3245 6.66659 9.99996 6.66659C7.67541 6.66659 5.57093 7.59933 4.04758 9.10736M18.3333 6.75034C16.2006 4.63909 13.2543 3.33325 9.99996 3.33325C6.74559 3.33325 3.79931 4.63909 1.66663 6.75034M11.6835 14.9999C11.6835 15.9204 10.9298 16.6666 9.99996 16.6666C9.07014 16.6666 8.31637 15.9204 8.31637 14.9999C8.31637 14.5397 8.50481 14.123 8.80948 13.8214C9.11415 13.5198 9.53505 13.3333 9.99996 13.3333C10.4649 13.3333 10.8858 13.5198 11.1904 13.8214C11.4951 14.123 11.6835 14.5397 11.6835 14.9999Z"
        stroke-width="1.2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  def icon(%{name: "identify"} = assigns) do
    ~H"""
    <svg class={["size-5", @class]} viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path
        d="M10.0001 10.0001V10.0009M10.0001 1.66675V5.00008M10.0001 15.0001V18.3334M18.3334 10.0001H15.0001M5.00008 10.0001H1.66675M16.6667 10.0001C16.6667 13.682 13.682 16.6667 10.0001 16.6667C6.31818 16.6667 3.33341 13.682 3.33341 10.0001C3.33341 6.31818 6.31818 3.33341 10.0001 3.33341C13.682 3.33341 16.6667 6.31818 16.6667 10.0001Z"
        stroke-width="1.2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end
end
