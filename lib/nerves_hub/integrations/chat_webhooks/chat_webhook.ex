defmodule NervesHub.Integrations.ChatWebhooks.ChatWebhook do
  @moduledoc """
  A chat channel an organization's device events are posted to, through the
  incoming webhook its chat service gave: a Microsoft Teams Workflows
  webhook or a Discord channel webhook (`provider`).

  The chat service gives NervesHub nothing to read the channel's name from,
  so `name` is whatever the person adding it calls it. The webhook's URL is
  all it takes to post to the channel, so it is stored encrypted
  (`NervesHub.Types.Encrypted`) and never shown again; `url_host` is kept in
  the clear to say where it points. Which URLs are accepted is the
  provider's call (`NervesHub.Integrations.ChatWebhooks.Provider`).

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
  alias NervesHub.Integrations.ChatWebhooks
  alias NervesHub.Integrations.ProductScope
  alias NervesHub.Products.Product
  alias NervesHub.Types.Encrypted

  @type t :: %__MODULE__{}

  schema "chat_webhooks" do
    belongs_to(:org, Org)

    many_to_many(:products, Product,
      join_through: "chat_webhook_products",
      join_keys: [chat_webhook_id: :id, product_id: :id],
      on_replace: :delete,
      where: [deleted_at: nil],
      preload_order: [asc: :name]
    )

    field(:provider, Ecto.Enum, values: [:teams, :discord])
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
  A new channel of the organization's, on `provider`, from the webhook URL
  the chat service gave and a name to know it by.
  """
  @spec create_changeset(Org.t(), ChatWebhooks.provider(), map(), ProductScope.found()) :: Ecto.Changeset.t()
  def create_changeset(%Org{} = org, provider, params, products) do
    %__MODULE__{org_id: org.id, provider: provider, products: []}
    |> cast(params, [:url])
    |> validate_required([:url], message: "paste the URL #{ChatWebhooks.provider(provider).label()} gave")
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
  def changeset(chat_webhook, params, products \\ nil) do
    chat_webhook
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
  # shows. A new URL for a channel posting turned off is the fix for what
  # turned it off, so it is turned back on; one a person turned off stays off.
  defp replace_url(changeset, %{"url" => url}) when is_binary(url) and url != "" do
    changeset
    |> cast(%{"url" => url}, [:url])
    |> put_url()
    |> turn_back_on()
    |> clear_failure()
  end

  defp replace_url(changeset, _params), do: changeset

  defp turn_back_on(changeset) do
    if changeset.valid? and not is_nil(get_field(changeset, :disabled_reason)) do
      put_change(changeset, :enabled, true)
    else
      changeset
    end
  end

  defp put_url(changeset) do
    case get_change(changeset, :url) do
      nil ->
        changeset

      url ->
        url = String.trim(url)

        case ChatWebhooks.provider(get_field(changeset, :provider)).check_url(url) do
          :ok -> changeset |> put_change(:url, url) |> put_change(:url_host, URI.parse(url).host)
          {:error, message} -> add_error(changeset, :url, message)
        end
    end
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
