defmodule NervesHubWeb.Components.BannerPicker do
  @moduledoc """
  Picker for product banner images.

  Renders the catalog of default theme banners (slim labelled ribbons with a
  photo credit link) and, optionally, an upload control for a custom banner.

  The parent LiveView owns the `phx-click` selection event and the upload
  (created with `allow_upload(:banner, ...)`). The picker is purely visual.
  """

  use NervesHubWeb, :html

  alias NervesHub.Products

  attr(:selected, :any,
    default: nil,
    doc: "currently active banner: nil (Blank), a default banner key (e.g. \"automotive.jpg\"), or :custom"
  )

  attr(:custom_url, :string,
    default: nil,
    doc: "URL of the existing custom banner; renders a Custom tile beside Blank when set"
  )

  attr(:pick_event, :string,
    default: "select-banner",
    doc: "name of the phx-click event sent when a default banner is clicked"
  )

  attr(:upload, :any,
    default: nil,
    doc: "the LV upload struct (from `@uploads.banner`); enables the upload UI when given"
  )

  def picker(assigns) do
    has_pending_upload = assigns[:upload] && Enum.any?(assigns.upload.entries)

    assigns =
      assigns
      |> assign(:banners, Products.default_banners())
      |> assign(:show_custom, assigns[:custom_url] || has_pending_upload)

    ~H"""
    <div class="flex flex-col gap-4">
      <p class="text-base-400 text-sm">
        Pick a theme — the preview at the top of the page updates as you click — or upload your own. You can change this later from product settings.
      </p>

      <div class="grid grid-cols-8 gap-2">
        <div class="flex flex-col gap-1 text-center">
          <span class="text-base-200 truncate text-[11px] leading-tight font-medium">Blank</span>
          <div
            phx-click={@pick_event}
            phx-value-banner=""
            aria-pressed={is_nil(@selected)}
            role="button"
            tabindex="0"
            class={[
              "bg-base-800 flex aspect-square cursor-pointer items-center justify-center overflow-hidden rounded-md border transition-all",
              if(is_nil(@selected),
                do: "border-indigo-500 ring-2 ring-indigo-500/40",
                else: "border-base-700 hover:border-base-500"
              )
            ]}
          >
          </div>
          <span class="text-base-500 text-[10px] leading-tight">&nbsp;</span>
        </div>

        <div :if={@show_custom} class="flex flex-col gap-1 text-center">
          <span class="text-base-200 truncate text-[11px] leading-tight font-medium">Custom</span>
          <div
            aria-pressed={@selected == :custom}
            class={[
              "flex aspect-square items-center justify-center overflow-hidden rounded-md border bg-cover bg-center transition-all",
              !@custom_url && "bg-base-800",
              if(@selected == :custom,
                do: "border-indigo-500 ring-2 ring-indigo-500/40",
                else: "border-base-700"
              )
            ]}
            style={@custom_url && "background-image: url('#{@custom_url}');"}
          >
            <span :if={!@custom_url} class="text-base-500 text-[10px]">upload</span>
          </div>
          <span class="text-base-500 text-[10px] leading-tight">&nbsp;</span>
        </div>

        <div :for={banner <- @banners} class="flex flex-col gap-1 text-center">
          <span class="text-base-200 truncate text-[11px] leading-tight font-medium">{banner.label}</span>
          <div
            phx-click={@pick_event}
            phx-value-banner={banner.key}
            aria-pressed={@selected == banner.key}
            role="button"
            tabindex="0"
            class={[
              "aspect-square cursor-pointer overflow-hidden rounded-md border bg-cover bg-center transition-all",
              if(@selected == banner.key,
                do: "border-indigo-500 ring-2 ring-indigo-500/40",
                else: "border-base-700 hover:border-base-500"
              )
            ]}
            style={"background-image: url('/images/default_banners/#{banner.key}');"}
          >
          </div>
          <a
            href={banner.pexels_url}
            target="_blank"
            rel="noopener"
            title={banner.photographer}
            class="hover:text-base-200 text-base-400 block truncate text-center text-[10px] leading-tight underline-offset-2 hover:underline"
          >
            {banner.photographer}
          </a>
        </div>
      </div>

      <p class="text-base-500 text-xs">
        All photos <a href="https://creativecommons.org/public-domain/cc0/" target="_blank" rel="noopener" class="underline">CC0</a>
        via <a href="https://www.pexels.com/" target="_blank" rel="noopener" class="underline">Pexels</a>.
      </p>

      <div :if={@upload} class="border-base-700 mt-2 flex flex-col gap-3 border-t pt-4">
        <p class="text-base-400 text-sm">
          Or upload your own. Recommended 1500×250, max 5 MB, JPG/PNG/WebP.
        </p>
        <div class="flex items-center gap-4">
          <div class="bg-base-800 border-base-700 hover:bg-base-700 flex gap-2 rounded border px-3 py-1.5 hover:cursor-pointer">
            <label for={@upload.ref} class="text-base-300 text-sm font-medium hover:cursor-pointer">
              Choose banner image
            </label>
            <.live_file_input upload={@upload} class="hidden" />
          </div>
          <div :for={entry <- @upload.entries} class="text-base-300 text-sm">
            {entry.client_name}
          </div>
        </div>
        <div :for={entry <- @upload.entries} class="flex flex-col gap-1">
          <div :for={err <- upload_errors(@upload, entry)} class="text-alert text-sm">
            {upload_error_to_string(err)}
          </div>
        </div>
        <div :for={err <- upload_errors(@upload)} class="text-alert text-sm">
          {upload_error_to_string(err)}
        </div>
      </div>
    </div>
    """
  end

  defp upload_error_to_string(:too_large), do: "File is too large (max 5MB)"
  defp upload_error_to_string(:not_accepted), do: "Invalid file type. Accepted: JPG, PNG, WebP"
  defp upload_error_to_string(:too_many_files), do: "Only one file can be uploaded at a time"
  defp upload_error_to_string(_), do: "Something went wrong uploading the file"
end
