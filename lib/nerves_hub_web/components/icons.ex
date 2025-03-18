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

  def icon(%{name: "trash"} = assigns) do
    ~H"""
    <svg class={["size-5", @class]} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path
        d="M15 7H9M15 7H18M15 7C15 5.34315 13.6569 4 12 4C10.3431 4 9 5.34315 9 7M9 7H6M4 7H6M6 7V18C6 19.1046 6.89543 20 8 20H16C17.1046 20 18 19.1046 18 18V7M18 7H20M10 11V16M14 16V11"
        stroke-width="1.2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  def icon(%{name: "settings"} = assigns) do
    ~H"""
    <svg class={[@class]} viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M8.33328 17.5L7.74757 17.6302C7.80857 17.9047 8.05206 18.1 8.33328 18.1V17.5ZM11.6666 17.5V18.1C11.9478 18.1 12.1913 17.9047 12.2523 17.6302L11.6666 17.5ZM11.6666 2.5L12.2523 2.36984C12.1913 2.09532 11.9478 1.9 11.6666 1.9V2.5ZM8.33328 2.5V1.9C8.05206 1.9 7.80857 2.09532 7.74757 2.36984L8.33328 2.5ZM2.67139 12.3066L2.26581 11.8645C2.05857 12.0545 2.01116 12.3631 2.15177 12.6066L2.67139 12.3066ZM4.33805 15.1934L3.81844 15.4934C3.95905 15.7369 4.24994 15.8501 4.51819 15.7657L4.33805 15.1934ZM17.3284 7.69337L17.734 8.13553C17.9413 7.94544 17.9887 7.63691 17.8481 7.39337L17.3284 7.69337ZM15.6618 4.80662L16.1814 4.50662C16.0408 4.26307 15.7499 4.14987 15.4816 4.2343L15.6618 4.80662ZM4.33805 4.80662L4.51819 4.23429C4.24994 4.14987 3.95905 4.26307 3.81844 4.50662L4.33805 4.80662ZM2.67139 7.69337L2.15177 7.39337C2.01116 7.63691 2.05857 7.94544 2.26581 8.13553L2.67139 7.69337ZM15.6618 15.1934L15.4816 15.7657C15.7499 15.8501 16.0408 15.7369 16.1814 15.4934L15.6618 15.1934ZM17.3284 12.3066L17.8481 12.6066C17.9887 12.3631 17.9413 12.0545 17.734 11.8645L17.3284 12.3066ZM15.768 9.12465L15.3625 8.68249C15.2154 8.81739 15.145 9.01659 15.1747 9.21394L15.768 9.12465ZM15.768 10.8753L15.1747 10.786C15.145 10.9834 15.2154 11.1826 15.3625 11.3175L15.768 10.8753ZM13.6414 14.5575L13.8215 13.9851C13.6308 13.9251 13.4227 13.964 13.2665 14.0889L13.6414 14.5575ZM12.1258 15.4339L11.907 14.8752C11.721 14.948 11.5834 15.1087 11.54 15.3037L12.1258 15.4339ZM7.87414 15.4339L8.45985 15.3037C8.41651 15.1087 8.27892 14.948 8.09288 14.8752L7.87414 15.4339ZM6.35851 14.5574L6.73334 14.0889C6.5772 13.964 6.3691 13.9251 6.17837 13.9851L6.35851 14.5574ZM4.23184 10.8753L4.63742 11.3174C4.78449 11.1825 4.85486 10.9833 4.82516 10.786L4.23184 10.8753ZM4.23184 9.1247L4.82516 9.21398C4.85486 9.01664 4.78449 8.81744 4.63742 8.68254L4.23184 9.1247ZM6.35852 5.44255L6.17839 6.01487C6.36912 6.0749 6.57722 6.03598 6.73335 5.91106L6.35852 5.44255ZM7.87414 4.56613L8.09288 5.12483C8.27892 5.05199 8.41651 4.89132 8.45985 4.69629L7.87414 4.56613ZM13.6413 5.44254L13.2665 5.91105C13.4227 6.03596 13.6308 6.07489 13.8215 6.01486L13.6413 5.44254ZM12.1258 4.56613L11.54 4.69629C11.5834 4.89132 11.721 5.05199 11.907 5.12483L12.1258 4.56613ZM8.33328 18.1H11.6666V16.9H8.33328V18.1ZM11.6666 1.9H8.33328V3.1H11.6666V1.9ZM2.15177 12.6066L3.81844 15.4934L4.85767 14.8934L3.191 12.0066L2.15177 12.6066ZM17.8481 7.39337L16.1814 4.50662L15.1422 5.10662L16.8088 7.99337L17.8481 7.39337ZM3.81844 4.50662L2.15177 7.39337L3.191 7.99337L4.85767 5.10662L3.81844 4.50662ZM16.1814 15.4934L17.8481 12.6066L16.8088 12.0066L15.1422 14.8934L16.1814 15.4934ZM15.1747 9.21394C15.2133 9.47001 15.2333 9.73248 15.2333 10H16.4333C16.4333 9.6725 16.4088 9.35035 16.3614 9.03537L15.1747 9.21394ZM16.1736 9.56681L17.734 8.13553L16.9229 7.2512L15.3625 8.68249L16.1736 9.56681ZM15.2333 10C15.2333 10.2675 15.2133 10.53 15.1747 10.786L16.3614 10.9646C16.4088 10.6496 16.4333 10.3275 16.4333 10H15.2333ZM17.734 11.8645L16.1736 10.4332L15.3625 11.3175L16.9229 12.7488L17.734 11.8645ZM13.4612 15.1298L15.4816 15.7657L15.8419 14.621L13.8215 13.9851L13.4612 15.1298ZM13.2665 14.0889C12.8585 14.4154 12.4009 14.6818 11.907 14.8752L12.3445 15.9926C12.9525 15.7545 13.5151 15.4268 14.0162 15.026L13.2665 14.0889ZM12.2523 17.6302L12.7115 15.564L11.54 15.3037L11.0809 17.3698L12.2523 17.6302ZM7.28843 15.564L7.74757 17.6302L8.91899 17.3698L8.45985 15.3037L7.28843 15.564ZM8.09288 14.8752C7.59902 14.6818 7.14138 14.4154 6.73334 14.0889L5.98368 15.0259C6.48473 15.4268 7.04736 15.7545 7.6554 15.9926L8.09288 14.8752ZM4.51819 15.7657L6.53864 15.1298L6.17837 13.9851L4.15792 14.621L4.51819 15.7657ZM4.82516 10.786C4.78663 10.5299 4.76661 10.2675 4.76661 10H3.56661C3.56661 10.3275 3.59113 10.6496 3.63852 10.9646L4.82516 10.786ZM3.82626 10.4331L2.26581 11.8645L3.07696 12.7488L4.63742 11.3174L3.82626 10.4331ZM4.76661 10C4.76661 9.73249 4.78663 9.47004 4.82516 9.21398L3.63852 9.03542C3.59113 9.35039 3.56661 9.67252 3.56661 10H4.76661ZM2.26581 8.13553L3.82627 9.56687L4.63742 8.68254L3.07696 7.2512L2.26581 8.13553ZM6.53866 4.87023L4.51819 4.23429L4.15792 5.37894L6.17839 6.01487L6.53866 4.87023ZM6.73335 5.91106C7.14139 5.58461 7.59903 5.31818 8.09288 5.12483L7.6554 4.00742C7.04737 4.24547 6.48474 4.57318 5.98369 4.97404L6.73335 5.91106ZM7.74757 2.36984L7.28843 4.43597L8.45985 4.69629L8.91899 2.63016L7.74757 2.36984ZM15.4816 4.2343L13.4612 4.87021L13.8215 6.01486L15.8419 5.37894L15.4816 4.2343ZM11.907 5.12483C12.4009 5.31818 12.8585 5.5846 13.2665 5.91105L14.0162 4.97402C13.5151 4.57317 12.9525 4.24547 12.3445 4.00742L11.907 5.12483ZM12.7115 4.43597L12.2523 2.36984L11.0809 2.63016L11.54 4.69629L12.7115 4.43597ZM11.8999 10C11.8999 11.0493 11.0493 11.9 9.99994 11.9V13.1C11.712 13.1 13.0999 11.7121 13.0999 10H11.8999ZM9.99994 11.9C8.9506 11.9 8.09994 11.0493 8.09994 10H6.89994C6.89994 11.7121 8.28786 13.1 9.99994 13.1V11.9ZM8.09994 10C8.09994 8.95066 8.9506 8.1 9.99994 8.1V6.9C8.28786 6.9 6.89994 8.28792 6.89994 10H8.09994ZM9.99994 8.1C11.0493 8.1 11.8999 8.95066 11.8999 10H13.0999C13.0999 8.28792 11.712 6.9 9.99994 6.9V8.1Z" />
    </svg>
    """
  end

  def icon(%{name: "unknown"} = assigns) do
    ~H"""
    <svg class={["size-4 stroke-2 stroke-zinc-500", @class]} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M7 12H17M22 12C22 17.5228 17.5228 22 12 22C6.47715 22 2 17.5228 2 12C2 6.47715 6.47715 2 12 2C17.5228 2 22 6.47715 22 12Z" stroke-linecap="round" stroke-linejoin="round" />
    </svg>
    """
  end

  def icon(%{name: "healthy"} = assigns) do
    ~H"""
    <svg class={["size-4 stroke-2 stroke-emerald-500", @class]} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M9 12L11 14L15 10M21 12C21 16.9706 16.9706 21 12 21C7.02944 21 3 16.9706 3 12C3 7.02944 7.02944 3 12 3C16.9706 3 21 7.02944 21 12Z" stroke-linecap="round" stroke-linejoin="round" />
    </svg>
    """
  end

  def icon(%{name: "warning"} = assigns) do
    ~H"""
    <svg class={["size-4 stroke-2 stroke-amber-500", @class]} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path
        d="M7.00013 4.51568C7.8989 3.91406 8.91208 3.47004 10.0001 3.22314M3.22314 10.0001C3.47004 8.91208 3.91406 7.8989 4.51568 7.00013M4.51568 17.0001C3.91406 16.1014 3.47004 15.0882 3.22314 14.0001M10.0001 20.7771C8.91208 20.5302 7.8989 20.0862 7.00013 19.4846M14.0001 20.7771C18.0081 19.8677 21.0001 16.2833 21.0001 12.0001C21.0001 7.71695 18.0081 4.1326 14.0001 3.22314M12.0001 8V12M12.0001 16V16.001"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  def icon(%{name: "unhealthy"} = assigns) do
    ~H"""
    <svg class={["size-4 stroke-2 stroke-red-500", @class]} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M12 8V13M12 16V16.01M21 12C21 16.9706 16.9706 21 12 21C7.02944 21 3 16.9706 3 12C3 7.02944 7.02944 3 12 3C16.9706 3 21 7.02944 21 12Z" stroke-linecap="round" stroke-linejoin="round" />
    </svg>
    """
  end

  def icon(%{name: "pinned"} = assigns) do
    ~H"""
    <svg class={["size-5", @class]} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path
        d="M4 20.0001L9 15.0001M9 15.0001L12.9556 18.9557C13.4558 19.456 14.3031 19.2928 14.5818 18.6425L16.8368 13.3809C16.9413 13.1371 17.1383 12.9448 17.3846 12.8463L20.5919 11.5634C21.2585 11.2967 21.4353 10.4354 20.9276 9.92778L14.0724 3.07249C13.5647 2.56485 12.7034 2.74164 12.4368 3.40821L11.1538 6.61555C11.0553 6.8618 10.863 7.05883 10.6193 7.16331L5.35761 9.41831C4.70735 9.69699 4.54417 10.5443 5.04442 11.0446L9 15.0001Z"
        stroke-width="1.2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  def icon(%{name: "unpinned"} = assigns) do
    ~H"""
    <svg class={["size-5", @class]} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path
        d="M4 20L9 15M9 15L14 20M9 15L4 10M8.5 8L10.6021 7.15917C10.8562 7.05753 11.0575 6.85618 11.1592 6.60208L12.4368 3.40807C12.7034 2.7415 13.5647 2.56471 14.0724 3.07235L20.9276 9.92764C21.4353 10.4353 21.2585 11.2966 20.5919 11.5632L17.3846 12.8462C17.1383 12.9447 16.9413 13.137 16.8368 13.3807L15.9286 15.5M2 2L22 22"
        stroke-width="1.2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  def icon(%{name: "open"} = assigns) do
    ~H"""
    <svg class={["size-5", @class]} viewBox="-2 -2 28 28" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path
        d="M 10.00,4.00
           C 10.00,4.00 6.00,4.00 6.00,4.00
             4.90,4.00 4.00,4.90 4.00,6.00
             4.00,6.00 4.00,18.00 4.00,18.00
             4.00,19.10 4.90,20.00 6.00,20.00
             6.00,20.00 18.00,20.00 18.00,20.00
             19.10,20.00 20.00,19.10 20.00,18.00
             20.00,18.00 20.00,14.00 20.00,14.00M 12.00,12.00
           C 12.00,12.00 20.00,4.00 20.00,4.00M 20.00,4.00
           C 20.00,4.00 20.00,9.00 20.00,9.00M 20.00,4.00
           C 20.00,4.00 15.00,4.00 15.00,4.00"
        stroke-width="1.2"
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke="#A1A1AA"
      />
    </svg>
    """
  end

  def icon(%{name: "folder-move"} = assigns) do
    ~H"""
    <svg class={["size-5", @class]} viewBox="-2 -2 28 28" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path
        d="M 21.00,12.00
           C 21.00,12.00 21.00,9.00 21.00,9.00
             21.00,7.90 20.10,7.00 19.00,7.00
             19.00,7.00 13.07,7.00 13.07,7.00
             12.40,7.00 11.78,6.67 11.41,6.11
             11.41,6.11 10.59,4.89 10.59,4.89
             10.22,4.33 9.60,4.00 8.93,4.00
             8.93,4.00 5.00,4.00 5.00,4.00
             3.90,4.00 3.00,4.90 3.00,6.00
             3.00,6.00 3.00,18.00 3.00,18.00
             3.00,19.10 3.90,20.00 5.00,20.00
             5.00,20.00 10.00,20.00 10.00,20.00M 21.00,18.00
           C 21.00,18.00 18.00,15.00 18.00,15.00M 21.00,18.00
           C 21.00,18.00 18.00,21.00 18.00,21.00M 21.00,18.00
           C 21.00,18.00 15.00,18.00 15.00,18.00"
        stroke-width="1.2"
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke="#A1A1AA"
      />
    </svg>
    """
  end
end
