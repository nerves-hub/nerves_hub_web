defmodule NervesHubWeb.Components.DeviceOnboarding do
  @moduledoc """
  What a product's devices list shows before any device has connected: the
  steps to connect the first one, with the product's shared secret filled in
  for members allowed to see it.
  """
  use NervesHubWeb, :component

  alias Phoenix.LiveView.JS

  attr(:product, :map, required: true)
  attr(:host, :string, required: true, doc: "the host devices connect to")

  attr(:secret, :map,
    default: nil,
    doc: "the product's active shared secret, only for members who can manage the product"
  )

  attr(:secret_reason, :atom,
    default: nil,
    values: [nil, :none, :hidden],
    doc: "why there is no `secret`: the product has none, or this member can't see it"
  )

  def render(assigns) do
    ~H"""
    <div id="device-onboarding" class="mx-auto w-full max-w-160 pt-14 pb-10">
      <h2 class="text-page-title text-content-strong">Connect your first device</h2>
      <p class="mt-1 text-sm/5.5 text-content-muted">
        Devices show up here the first time they connect. Add <code class="font-mono text-content-body">nerves_hub_link</code>
        to your Nerves project and point it at <code class="font-mono text-content-body">{@product.name}</code>.
      </p>

      <ol class="mt-5 rounded-card border border-line-default bg-surface-raised">
        <.step number={1}>
          <:title>Add the dependency to <code class="font-mono">mix.exs</code></:title>
          <.code_block id="onboarding-dependency" text={~s({:nerves_hub_link, "~> 2.0"})} />
        </.step>

        <.step :if={@secret} number={2}>
          <:title>Add this to <code class="font-mono">config/config.exs</code></:title>
          <.code_block
            id="onboarding-config"
            text={config(@host, @secret.key, @secret.secret)}
            masked={config(@host, @secret.key, String.duplicate("•", 20))}
          />
          <p class="mt-2 flex items-center gap-1.5 text-xs/4 text-content-muted">
            <button
              id="onboarding-show-secret"
              type="button"
              class="flex cursor-pointer items-center gap-1.5 text-content-body underline decoration-line-strong underline-offset-3 hover:text-content-strong"
              phx-click={
                JS.toggle_class("hidden", to: "#onboarding-config-masked")
                |> JS.toggle_class("hidden", to: "#onboarding-config-shown")
                |> JS.toggle_class("hidden", to: "#onboarding-show-secret > span")
              }
            >
              <span class="lucide-eye size-3.5 text-content-muted" aria-hidden="true"></span>
              <span>Show the secret</span>
              <span class="lucide-eye-off hidden size-3.5 text-content-muted" aria-hidden="true"></span>
              <span class="hidden">Hide the secret</span>
            </button>
            <span>· the copy button includes it</span>
          </p>
        </.step>

        <.step :if={is_nil(@secret)} number={2}>
          <:title>Configure <code class="font-mono">nerves_hub_link</code></:title>
          <p id="onboarding-no-secret" class="text-ui/5 text-content-muted">
            {no_secret(@secret_reason)} The
            <a class="text-content-body underline decoration-line-strong underline-offset-3 hover:text-content-strong" href="https://hexdocs.pm/nerves_hub_link" target="_blank">
              nerves_hub_link documentation
            </a>
            covers every way to connect.
          </p>
        </.step>

        <li class="flex gap-3 px-5 py-4">
          <span class="relative mt-1 flex size-5 shrink-0 items-center justify-center" aria-hidden="true">
            <span class="absolute size-4 animate-ping rounded-full bg-primary/25 motion-reduce:animate-none"></span>
            <span class="size-2 rounded-full bg-primary"></span>
          </span>
          <div>
            <p class="text-ui/5 font-medium text-content-strong">Waiting for the first device to connect…</p>
            <p class="text-ui/5 text-content-muted">Flash the firmware and boot it. This page updates on its own when it connects.</p>
          </div>
        </li>
      </ol>

      <div :if={@secret_reason != :none} id="onboarding-production" class="mt-5 flex gap-3 rounded-card border border-line-subtle bg-surface-muted px-4 py-3.5">
        <span class="mt-0.5 lucide-shield size-4 text-content-muted" aria-hidden="true"></span>
        <div>
          <p class="text-ui/5 font-medium text-content-strong">Going to production?</p>
          <p class="text-ui/5 text-content-muted">
            A shared secret is fine for trying things out. In production, give each device its own identity with a certificate: the
            <a
              class="text-content-body underline decoration-line-strong underline-offset-3 hover:text-content-strong"
              href="https://hexdocs.pm/nerves_hub_link/NervesHubLink.Configurator.LocalCert.html"
              target="_blank"
            >LocalCert</a>
            or
            <a
              class="text-content-body underline decoration-line-strong underline-offset-3 hover:text-content-strong"
              href="https://hexdocs.pm/nerves_hub_link/NervesHubLink.Configurator.NervesKey.html"
              target="_blank"
            >NervesKey</a>
            configurator.
          </p>
        </div>
      </div>
    </div>
    """
  end

  attr(:number, :integer, required: true)
  slot(:title, required: true)
  slot(:inner_block, required: true)

  defp step(assigns) do
    ~H"""
    <li class="flex gap-3 border-b border-line-default px-5 py-4">
      <span class="mt-px flex size-5 shrink-0 items-center justify-center rounded-full border border-line-control font-mono text-label text-content-muted">
        {@number}
      </span>
      <div class="min-w-0 flex-1">
        <p class="mb-2.5 text-ui/5 font-medium text-content-strong">{render_slot(@title)}</p>
        {render_slot(@inner_block)}
      </div>
    </li>
    """
  end

  attr(:id, :string, required: true)
  attr(:text, :string, required: true, doc: "the code, which the copy button copies")
  attr(:masked, :string, default: nil, doc: "what to show instead until the reader asks to see `text`")

  # Code on a dark ground in either theme, as a terminal would show it. The
  # code is kept on one line of the template, since whitespace in a <pre> shows.
  defp code_block(assigns) do
    ~H"""
    <div class="relative rounded border border-line-default bg-zinc-950 light:border-transparent light:bg-zinc-900">
      <pre :if={is_nil(@masked)} class={pre_class()}><code id={@id}>{@text}</code></pre>
      <pre :if={@masked} class={pre_class()}><code id={@id}><span id={"#{@id}-masked"}>{@masked}</span><span id={"#{@id}-shown"} class="hidden">{@text}</span></code></pre>
      <button
        id={"#{@id}-copy"}
        type="button"
        phx-hook="CopyToClipboard"
        data-copy-value={@text}
        aria-label="Copy"
        title="Copy"
        class="absolute top-2 right-2 flex size-7 cursor-pointer items-center justify-center rounded text-zinc-400 hover:bg-zinc-800 hover:text-zinc-100"
      >
        <span data-icon="copy" class="lucide-copy size-3.5" aria-hidden="true"></span>
        <span data-icon="check" class="lucide-check hidden size-3.5 text-emerald-400" aria-hidden="true"></span>
      </button>
    </div>
    """
  end

  defp pre_class(), do: "overflow-x-auto py-3 pr-12 pl-3.5 font-mono text-xs/5 text-zinc-200"

  defp config(host, key, secret) do
    """
    config :nerves_hub_link,
      host: "#{host}",
      remote_iex: true,
      shared_secret: [
        product_key: "#{key}",
        product_secret: "#{secret}"
      ]\
    """
  end

  defp no_secret(:none), do: "This product has no shared secret, so each device connects with its own certificate."

  defp no_secret(_hidden),
    do: "The shared secret devices connect with is only shown to members who can manage this product."
end
