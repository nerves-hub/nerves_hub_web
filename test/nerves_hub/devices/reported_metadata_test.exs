defmodule NervesHub.Devices.ReportedMetadataTest do
  use ExUnit.Case, async: true

  alias NervesHub.Devices.ReportedMetadata

  describe "trim/1" do
    test "keeps metadata within the limits as it is" do
      metadata = %{"placement" => "the shed", "board_revision" => "c", "slot" => 3, "spare" => true}

      assert {^metadata, %{reasons: [], count: 0, example_key: nil}} = ReportedMetadata.trim(metadata)
    end

    test "drops the keys the platform writes itself" do
      assert {%{"placement" => "the shed"}, %{reasons: [:reserved], count: 3}} =
               ReportedMetadata.trim(%{
                 "placement" => "the shed",
                 "location" => %{},
                 "connection_types" => ["wifi"],
                 "device_api_version" => "9.9.9"
               })
    end

    test "drops a key or a value too long to store" do
      long_key = String.duplicate("k", ReportedMetadata.max_key_bytes() + 1)
      long_value = String.duplicate("v", ReportedMetadata.max_value_bytes())

      assert {%{"placement" => "the shed"}, %{reasons: [:too_long], count: 3}} =
               ReportedMetadata.trim(%{
                 "placement" => "the shed",
                 long_key => "x",
                 "notes" => long_value,
                 "nested" => %{"notes" => long_value}
               })
    end

    test "measures a value as JSON, so a short nested value is kept" do
      metadata = %{"sensors" => %{"left" => "ok", "right" => "ok"}}

      assert {^metadata, %{count: 0}} = ReportedMetadata.trim(metadata)
    end

    test "keeps the first keys in sorted order, so the same ones are dropped every time" do
      metadata = Map.new(1..40, &{"key_#{String.pad_leading("#{&1}", 2, "0")}", &1})

      {kept, dropped} = ReportedMetadata.trim(metadata)

      assert map_size(kept) == ReportedMetadata.max_keys()
      assert Map.has_key?(kept, "key_01")
      assert Map.has_key?(kept, "key_32")
      refute Map.has_key?(kept, "key_33")
      assert dropped == %{reasons: [:too_many], count: 8, example_key: "key_33"}
    end

    test "names every reason, and counts every key, when more than one applies" do
      metadata =
        Map.merge(
          Map.new(1..33, &{"key_#{String.pad_leading("#{&1}", 2, "0")}", &1}),
          %{"location" => %{}, "notes" => String.duplicate("v", 300)}
        )

      assert {_kept, %{reasons: [:reserved, :too_long, :too_many], count: 3, example_key: "location"}} =
               ReportedMetadata.trim(metadata)
    end
  end
end
