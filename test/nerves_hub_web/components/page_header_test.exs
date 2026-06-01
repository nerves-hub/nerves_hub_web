defmodule NervesHubWeb.Components.PageHeaderTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias NervesHubWeb.Components.PageHeader

  @endpoint NervesHubWeb.Endpoint

  @banner "/images/default_banners/automotive.jpg"

  describe "simple/1" do
    test "renders the title as an h1 when given" do
      html = render_component(&PageHeader.simple/1, %{title: "All Devices"})

      assert html =~ "<h1"
      assert html =~ "All Devices"
    end

    test "omits the h1 when no title is given" do
      html = render_component(&PageHeader.simple/1, %{})

      refute html =~ "<h1"
    end

    test "renders inner_block content next to the title" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <PageHeader.simple title="Devices">
          <div data-role="counter">42</div>
        </PageHeader.simple>
        """)

      assert html =~ ~s(data-role="counter")
      assert html =~ "42"
    end

    test "renders the actions slot" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <PageHeader.simple title="Devices">
          <:actions>
            <button data-role="export">Export</button>
          </:actions>
        </PageHeader.simple>
        """)

      assert html =~ ~s(data-role="export")
    end

    test "omits the actions wrapper when the slot is empty" do
      html = render_component(&PageHeader.simple/1, %{title: "Devices"})

      # Actions wrapper has gap-2 alongside relative flex items-center
      refute html =~ ~s(class="relative flex items-center gap-2")
    end

    test "adds the bottom border by default" do
      html = render_component(&PageHeader.simple/1, %{title: "Devices"})

      assert html =~ "border-b"
    end

    test "omits the bottom border when border={false}" do
      html = render_component(&PageHeader.simple/1, %{title: "Devices", border: false})

      refute html =~ "border-b"
    end

    test "does not render the banner background or gradients without banner_url" do
      html = render_component(&PageHeader.simple/1, %{title: "Devices"})

      refute html =~ "background-image"
      refute html =~ "bg-linear-to-r"
      refute html =~ "bg-linear-to-t"
    end

    test "renders the banner background and horizontal gradient with banner_url" do
      html =
        render_component(&PageHeader.simple/1, %{title: "Devices", banner_url: @banner})

      assert html =~ "background-image: url(&#39;#{@banner}&#39;)"
      assert html =~ "bg-linear-to-r"
      refute html =~ "bg-linear-to-t"
    end

    test "renders the vertical fade when fade_bottom={true}" do
      html =
        render_component(&PageHeader.simple/1, %{
          title: "Devices",
          banner_url: @banner,
          fade_bottom: true
        })

      assert html =~ "bg-linear-to-r"
      assert html =~ "bg-linear-to-t"
    end

    test "does not render the vertical fade without a banner, even when fade_bottom={true}" do
      html =
        render_component(&PageHeader.simple/1, %{title: "Devices", fade_bottom: true})

      refute html =~ "bg-linear-to-t"
    end

    test "appends the extra class" do
      html =
        render_component(&PageHeader.simple/1, %{title: "Devices", class: "custom-class"})

      assert html =~ "custom-class"
    end
  end

  describe "detail/1" do
    test "renders the title slot" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <PageHeader.detail>
          <:title>
            <h1 data-role="title">device-abc</h1>
          </:title>
        </PageHeader.detail>
        """)

      assert html =~ ~s(data-role="title")
      assert html =~ "device-abc"
    end

    test "renders the status slot when provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <PageHeader.detail>
          <:status>
            <span data-role="status-dot"></span>
          </:status>
          <:title>
            <h1>device-abc</h1>
          </:title>
        </PageHeader.detail>
        """)

      assert html =~ ~s(data-role="status-dot")
    end

    test "renders the actions slot when provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <PageHeader.detail>
          <:title>
            <h1>device-abc</h1>
          </:title>
          <:actions>
            <button data-role="reboot">Reboot</button>
          </:actions>
        </PageHeader.detail>
        """)

      assert html =~ ~s(data-role="reboot")
    end

    test "does not add a bottom border by default" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <PageHeader.detail>
          <:title>
            <h1>device-abc</h1>
          </:title>
        </PageHeader.detail>
        """)

      refute html =~ "border-b"
    end

    test "adds the bottom border when border={true}" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <PageHeader.detail border={true}>
          <:title>
            <h1>device-abc</h1>
          </:title>
        </PageHeader.detail>
        """)

      assert html =~ "border-b"
    end

    test "does not render the banner background or gradients without banner_url" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <PageHeader.detail>
          <:title>
            <h1>device-abc</h1>
          </:title>
        </PageHeader.detail>
        """)

      refute html =~ "background-image"
      refute html =~ "bg-linear-to-r"
      refute html =~ "bg-linear-to-t"
    end

    test "renders the banner background and horizontal gradient with banner_url" do
      assigns = %{banner: @banner}

      html =
        rendered_to_string(~H"""
        <PageHeader.detail banner_url={@banner}>
          <:title>
            <h1>device-abc</h1>
          </:title>
        </PageHeader.detail>
        """)

      assert html =~ "background-image: url(&#39;#{@banner}&#39;)"
      assert html =~ "bg-linear-to-r"
      refute html =~ "bg-linear-to-t"
    end

    test "renders the vertical fade when fade_bottom={true}" do
      assigns = %{banner: @banner}

      html =
        rendered_to_string(~H"""
        <PageHeader.detail banner_url={@banner} fade_bottom={true}>
          <:title>
            <h1>device-abc</h1>
          </:title>
        </PageHeader.detail>
        """)

      assert html =~ "bg-linear-to-r"
      assert html =~ "bg-linear-to-t"
    end

    test "does not render the vertical fade without a banner, even when fade_bottom={true}" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <PageHeader.detail fade_bottom={true}>
          <:title>
            <h1>device-abc</h1>
          </:title>
        </PageHeader.detail>
        """)

      refute html =~ "bg-linear-to-t"
    end

    test "appends the extra class" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <PageHeader.detail class="custom-class">
          <:title>
            <h1>device-abc</h1>
          </:title>
        </PageHeader.detail>
        """)

      assert html =~ "custom-class"
    end
  end
end
