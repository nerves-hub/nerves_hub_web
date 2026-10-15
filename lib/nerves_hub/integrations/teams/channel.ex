defmodule NervesHub.Integrations.Teams.Channel do
  @moduledoc """
  A Microsoft Teams channel an organization's device events are posted to,
  through a Workflows webhook somebody made in that channel.

  Teams gives NervesHub nothing to read the channel's name from, so `name`
  is whatever the person adding it calls it. The webhook's URL carries the
  signature that lets anyone holding it post to the channel, so it is stored
  encrypted (`NervesHub.Types.Encrypted`) and never shown again; `url_host`
  is kept in the clear to say where it points.

  Like a Slack channel, it hears every product in the organization
  (`all_products`) or the products it lists, and is sent the events it names
  (`NervesHub.Integrations.ChannelEvents`). `last_error` and `last_error_at`
  describe the channel as posting last found it; `disabled_reason` is set
  when posting turned it off, and cleared when a person turns it back on.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.Org
  alias NervesHub.Integrations.ChannelEvents
  alias NervesHub.Integrations.ProductScope
  alias NervesHub.Integrations.Teams
  alias NervesHub.Products.Product
  alias NervesHub.Types.Encrypted
  alias NervesHub.Webhooks.Destination

  @type t :: %__MODULE__{}

  # Where Teams' Workflows webhooks live: Power Automate's trigger URLs, on
  # its older host and its newer one. Anything else is somebody else's
  # endpoint, which a webhook is for.
  @default_hosts [".logic.azure.com", ".api.powerplatform.com"]

  # Office 365 connector URLs, which Microsoft retired in May 2026.
  @connector_hosts ["webhook.office.com", "outlook.office.com"]

  schema "teams_channels" do
    belongs_to(:org, Org)

    many_to_many(:products, Product,
      join_through: "teams_channel_products",
      join_keys: [channel_id: :id, product_id: :id],
      on_replace: :delete,
      where: [deleted_at: nil],
      preload_order: [asc: :name]
    )

    field(:name, :string)
    field(:url, Encrypted, redact: true)
    field(:url_host, :string)
    field(:events, {:array, :string}, default: [])
    field(:all_products, :boolean, default: true)
    field(:enabled, :boolean, default: true)
    field(:disabled_reason, :string)
    field(:last_error, :string)
    field(:last_error_at, :utc_datetime)

    timestamps()
  end

  @doc """
  A new channel for the organization, from the webhook URL Teams gave and a
  name to know it by.
  """
  @spec create_changeset(Org.t(), map(), ProductScope.found()) :: Ecto.Changeset.t()
  def create_changeset(%Org{} = org, params, products) do
    %__MODULE__{org_id: org.id, products: []}
    |> cast(params, [:url])
    |> validate_required([:url], message: "paste the URL Teams gave the workflow")
    |> changeset(params, products)
  end

  @doc """
  The fields a person edits: the name, events, products, and whether it is
  on, and the webhook URL when one is given in its place. `products` is what
  `params` named, already looked up in the organization
  (`NervesHub.Integrations.ProductScope`); the channel's `products` must be
  loaded.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map(), ProductScope.found()) :: Ecto.Changeset.t()
  def changeset(channel, params, products \\ nil) do
    channel
    |> cast(params, [:name, :events, :all_products, :enabled])
    |> replace_url(params)
    |> validate_required([:name, :all_products])
    |> validate_length(:name, max: 80)
    |> update_change(:events, &Enum.uniq/1)
    |> validate_subset(:events, ChannelEvents.keys(), message: "contains an event that does not exist")
    |> validate_some_events()
    |> ProductScope.put(products)
    |> clear_failure_on_enable()
    |> foreign_key_constraint(:org_id)
  end

  # A URL given is checked here, for a new channel as for an edited one.
  # Leaving it empty when editing keeps the one saved, which the form never
  # shows.
  defp replace_url(changeset, %{"url" => url}) when is_binary(url) and url != "" do
    changeset
    |> cast(%{"url" => url}, [:url])
    |> put_url()
    |> clear_failure()
  end

  defp replace_url(changeset, _params), do: changeset

  defp put_url(changeset) do
    case get_change(changeset, :url) do
      nil ->
        changeset

      url ->
        url = String.trim(url)

        case check_url(url) do
          :ok -> changeset |> put_change(:url, url) |> put_change(:url_host, URI.parse(url).host)
          {:error, message} -> add_error(changeset, :url, message)
        end
    end
  end

  @doc """
  Whether `url` is a Teams Workflows webhook NervesHub may post to, with a
  message for the form when it is not.

  The hosts accepted are Power Automate's (`config :nerves_hub,
  NervesHub.Integrations.Teams, hosts:` overrides them, for a sovereign cloud such as
  GCC High), and the address must be one a webhook could be sent to
  (`NervesHub.Webhooks.Destination`).
  """
  @spec check_url(String.t()) :: :ok | {:error, String.t()}
  def check_url(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: "https", host: host}} when is_binary(host) and host != "" ->
        with :ok <- Destination.validate_url(url), do: check_host(String.downcase(host))

      {:ok, %URI{}} ->
        {:error, "must start with https://"}

      {:error, _invalid_part} ->
        {:error, "is not a valid URL"}
    end
  end

  defp check_host(host) do
    cond do
      Enum.any?(@connector_hosts, &String.ends_with?(host, &1)) ->
        {:error,
         "is an Office 365 connector URL, which Microsoft retired in 2026. Add a Workflows webhook to the channel instead."}

      Enum.any?(hosts(), &String.ends_with?(host, &1)) ->
        :ok

      true ->
        {:error, "must be the URL Teams gives a Workflows webhook"}
    end
  end

  defp hosts() do
    :nerves_hub
    |> Application.get_env(Teams, [])
    |> Keyword.get(:hosts, @default_hosts)
  end

  defp validate_some_events(changeset) do
    if get_field(changeset, :events) == [] do
      add_error(changeset, :events, "choose at least one event")
    else
      changeset
    end
  end

  # A person turning a channel back on has dealt with whatever turned it off.
  defp clear_failure_on_enable(changeset) do
    if get_change(changeset, :enabled) == true, do: clear_failure(changeset), else: changeset
  end

  defp clear_failure(changeset) do
    changeset
    |> put_change(:disabled_reason, nil)
    |> put_change(:last_error, nil)
    |> put_change(:last_error_at, nil)
  end
end
