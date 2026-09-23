defmodule NervesHub.ScriptRunnersTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Accounts.Scope
  alias NervesHub.AuditLogs
  alias NervesHub.Fixtures
  alias NervesHub.ScriptRunners
  alias NervesHub.ScriptRunners.ScriptRunner
  alias NervesHub.ScriptRunners.ScriptRunnerDevice
  alias NervesHub.Workers.ScriptRunnerDispatch

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)

    %{user: user, org: org, product: product, firmware: firmware}
  end

  defp device(ctx, params \\ %{}) do
    Fixtures.device_fixture(ctx.org, ctx.product, ctx.firmware, params)
  end

  defp create(ctx, params) do
    ScriptRunners.create(ctx.product, ctx.user, Map.merge(%{name: "Say hi", text: "IO.puts(:hi)"}, params))
  end

  defp targeted_device_ids(runner) do
    runner
    |> ScriptRunners.device_results()
    |> Enum.map(& &1.device_id)
    |> Enum.sort()
  end

  describe "create/3 targeting by tags" do
    test "'require all' selects only devices carrying every tag", ctx do
      both = device(ctx, %{tags: ["production", "cellular"]})
      _one = device(ctx, %{tags: ["production"]})
      _none = device(ctx, %{tags: ["staging"]})

      {:ok, runner, []} =
        create(ctx, %{
          filter_type: :tags,
          filter: %{tags: ["production", "cellular"], tag_operator: :and}
        })

      assert targeted_device_ids(runner) == [both.id]
      assert runner.device_count == 1
    end

    test "'allow any' selects devices carrying at least one tag", ctx do
      both = device(ctx, %{tags: ["production", "cellular"]})
      one = device(ctx, %{tags: ["production"]})
      _none = device(ctx, %{tags: ["staging"]})

      {:ok, runner, []} =
        create(ctx, %{
          filter_type: :tags,
          filter: %{tags: ["production", "cellular"], tag_operator: :or}
        })

      assert targeted_device_ids(runner) == Enum.sort([both.id, one.id])
    end

    test "a tag is matched whole, not as a substring", ctx do
      _prefixed = device(ctx, %{tags: ["production-eu"]})
      exact = device(ctx, %{tags: ["production"]})

      {:ok, runner, []} =
        create(ctx, %{filter_type: :tags, filter: %{tags: ["production"], tag_operator: :or}})

      assert targeted_device_ids(runner) == [exact.id],
             "substring matching would target devices the operator did not ask for"
    end

    test "a device with no tags is never selected", ctx do
      _untagged = device(ctx, %{tags: []})
      tagged = device(ctx, %{tags: ["production"]})

      {:ok, runner, []} =
        create(ctx, %{filter_type: :tags, filter: %{tags: ["production"], tag_operator: :and}})

      assert targeted_device_ids(runner) == [tagged.id]
    end
  end

  describe "create/3 targeting by identifiers" do
    test "selects the named devices and reports the ones that matched nothing", ctx do
      first = device(ctx)
      second = device(ctx)

      {:ok, runner, unmatched} =
        create(ctx, %{
          filter_type: :identifiers,
          filter: %{identifiers: "#{first.identifier},#{second.identifier},ghost-device"}
        })

      assert targeted_device_ids(runner) == Enum.sort([first.id, second.id])
      assert unmatched == ["ghost-device"]
    end

    test "accepts what a person pastes: newlines, spacing, blanks and repeats", ctx do
      first = device(ctx)
      second = device(ctx)

      {:ok, runner, []} =
        create(ctx, %{
          filter_type: :identifiers,
          filter: %{identifiers: "  #{first.identifier} \n\n #{second.identifier},#{first.identifier},  "}
        })

      assert targeted_device_ids(runner) == Enum.sort([first.id, second.id]),
             "a repeated identifier must not target the same device twice"
    end
  end

  describe "create/3 targeting by deployment groups" do
    test "selects the devices in any of the named groups", ctx do
      group_one = Fixtures.deployment_group_fixture(ctx.firmware, %{name: "one", user: ctx.user})
      group_two = Fixtures.deployment_group_fixture(ctx.firmware, %{name: "two", user: ctx.user})

      in_one = device(ctx, %{deployment_id: group_one.id})
      in_two = device(ctx, %{deployment_id: group_two.id})
      _in_neither = device(ctx)

      {:ok, runner, []} =
        create(ctx, %{
          filter_type: :deployment_groups,
          filter: %{deployment_group_ids: [group_one.id, group_two.id]}
        })

      assert targeted_device_ids(runner) == Enum.sort([in_one.id, in_two.id])
    end
  end

  describe "create/3 scoping" do
    test "never targets another product's devices", ctx do
      other_product = Fixtures.product_fixture(ctx.user, ctx.org, %{name: "other"})
      other_key = Fixtures.org_key_fixture(ctx.org, ctx.user)
      other_firmware = Fixtures.firmware_fixture(other_key, other_product)

      mine = device(ctx, %{tags: ["production"]})

      _theirs =
        Fixtures.device_fixture(ctx.org, other_product, other_firmware, %{tags: ["production"]})

      {:ok, runner, []} =
        create(ctx, %{filter_type: :tags, filter: %{tags: ["production"], tag_operator: :or}})

      assert targeted_device_ids(runner) == [mine.id]
    end

    test "never targets a soft deleted device", ctx do
      kept = device(ctx, %{tags: ["production"]})
      deleted = device(ctx, %{tags: ["production"]})

      {:ok, _deleted} = NervesHub.Repo.soft_delete(deleted)

      {:ok, runner, []} =
        create(ctx, %{filter_type: :tags, filter: %{tags: ["production"], tag_operator: :or}})

      assert targeted_device_ids(runner) == [kept.id]
    end
  end

  describe "create/3 validation" do
    test "refuses a run that would target nothing", ctx do
      assert {:error, :no_devices} =
               create(ctx, %{filter_type: :tags, filter: %{tags: ["nobody-has-this"], tag_operator: :or}})
    end

    test "requires the values the chosen filter type needs", ctx do
      assert {:error, changeset} = create(ctx, %{filter_type: :tags, filter: %{tags: []}})
      assert "at least one tag is required" in errors_on(changeset).filter

      assert {:error, changeset} = create(ctx, %{filter_type: :identifiers, filter: %{identifiers: []}})
      assert "at least one device identifier is required" in errors_on(changeset).filter

      assert {:error, changeset} =
               create(ctx, %{filter_type: :deployment_groups, filter: %{deployment_group_ids: []}})

      assert "at least one deployment group is required" in errors_on(changeset).filter
    end

    test "requires a tag operator to be chosen when filtering by tags", ctx do
      _device = device(ctx, %{tags: ["production"]})

      # "All of these tags" and "any of these tags" target different fleets, so
      # leaving it out must not quietly pick one.
      assert {:error, changeset} = create(ctx, %{filter_type: :tags, filter: %{tags: ["production"]}})
      assert Enum.any?(errors_on(changeset).filter, &(&1 =~ "tag operator must be chosen"))

      assert {:error, changeset} =
               create(ctx, %{filter_type: :tags, filter: %{tags: ["production"], tag_operator: nil}})

      assert Enum.any?(errors_on(changeset).filter, &(&1 =~ "tag operator must be chosen"))
    end

    test "rejects a tag operator that is not one of the two", ctx do
      _device = device(ctx, %{tags: ["production"]})

      assert {:error, changeset} =
               create(ctx, %{filter_type: :tags, filter: %{tags: ["production"], tag_operator: :maybe}})

      refute changeset.valid?
    end

    test "accepts either operator", ctx do
      _device = device(ctx, %{tags: ["production"]})

      for operator <- ScriptRunner.tag_operators() do
        assert {:ok, runner, []} =
                 create(ctx, %{filter_type: :tags, filter: %{tags: ["production"], tag_operator: operator}})

        assert runner.filter.tag_operator == operator
      end
    end

    test "the other filter types do not ask for an operator", ctx do
      first = device(ctx)

      assert {:ok, _runner, []} =
               create(ctx, %{filter_type: :identifiers, filter: %{identifiers: first.identifier}})

      group = Fixtures.deployment_group_fixture(ctx.firmware, %{name: "g", user: ctx.user})
      _in_group = device(ctx, %{deployment_id: group.id})

      assert {:ok, _runner, []} =
               create(ctx, %{filter_type: :deployment_groups, filter: %{deployment_group_ids: [group.id]}})
    end

    test "requires the script text", ctx do
      _device = device(ctx, %{tags: ["production"]})

      assert {:error, changeset} =
               ScriptRunners.create(ctx.product, ctx.user, %{
                 name: "Nameless code",
                 filter_type: :tags,
                 filter: %{tags: ["production"], tag_operator: :or}
               })

      assert "can't be blank" in errors_on(changeset).text
    end

    test "requires a name", ctx do
      _device = device(ctx, %{tags: ["production"]})

      assert {:error, changeset} =
               ScriptRunners.create(ctx.product, ctx.user, %{
                 text: "IO.puts(:hi)",
                 filter_type: :tags,
                 filter: %{tags: ["production"], tag_operator: :or}
               })

      assert "can't be blank" in errors_on(changeset).name
    end

    test "refuses a name longer than the column", ctx do
      _device = device(ctx, %{tags: ["production"]})

      assert {:error, changeset} =
               create(ctx, %{
                 name: String.duplicate("a", 256),
                 filter_type: :tags,
                 filter: %{tags: ["production"], tag_operator: :or}
               })

      assert Enum.any?(errors_on(changeset).name, &(&1 =~ "should be at most"))
    end
  end

  describe "create/3 recording" do
    test "stores the code that ran, and offers no way to change it", ctx do
      _device = device(ctx, %{tags: ["production"]})

      {:ok, runner, []} =
        create(ctx, %{
          text: "System.cmd(\"uptime\", [])",
          language: :shell,
          filter_type: :tags,
          filter: %{tags: ["production"], tag_operator: :or}
        })

      assert runner.text == "System.cmd(\"uptime\", [])"
      assert runner.language == :shell

      # These rows are history: nothing in the context updates `text`, which is
      # what lets a run still show what ran after its source script is edited.
      refute function_exported?(ScriptRunners, :update, 3)
      refute function_exported?(ScriptRunner, :update_changeset, 3)
    end

    test "starts every device pending, and counts them", ctx do
      _first = device(ctx, %{tags: ["production"]})
      _second = device(ctx, %{tags: ["production"]})

      {:ok, runner, []} =
        create(ctx, %{filter_type: :tags, filter: %{tags: ["production"], tag_operator: :or}})

      assert runner.status == :pending
      assert runner.device_count == 2
      assert ScriptRunners.status_counts(runner) == %{pending: 2}
    end

    test "enqueues one dispatch job to work through the devices", ctx do
      _device = device(ctx, %{tags: ["production"]})

      {:ok, runner, []} =
        create(ctx, %{filter_type: :tags, filter: %{tags: ["production"], tag_operator: :or}})

      # Inserted in the same transaction as the device rows: a run whose devices
      # were recorded with no job to work through them would never start.
      assert_enqueued(worker: ScriptRunnerDispatch, args: %{script_runner_id: runner.id})
    end

    test "a run that targets nothing enqueues no work", ctx do
      assert {:error, :no_devices} =
               create(ctx, %{filter_type: :tags, filter: %{tags: ["nobody"], tag_operator: :or}})

      refute_enqueued(worker: ScriptRunnerDispatch)
    end

    test "audits the run against the product", ctx do
      _device = device(ctx, %{tags: ["production"]})

      {:ok, runner, []} =
        create(ctx, %{filter_type: :tags, filter: %{tags: ["production"], tag_operator: :or}})

      logs = AuditLogs.logs_for(ctx.product)

      assert Enum.any?(logs, fn log ->
               log.description =~ "ran a script named #{runner.name} with id #{runner.id} on 1 devices"
             end)
    end

    test "accepts a scope in place of a product", ctx do
      device = device(ctx, %{tags: ["production"]})

      scope =
        ctx.user
        |> Scope.for_user()
        |> Scope.put_org(ctx.org)
        |> Scope.put_product(ctx.product)

      {:ok, runner, []} =
        ScriptRunners.create(scope, ctx.user, %{
          name: "Say hi",
          text: "IO.puts(:hi)",
          filter_type: :tags,
          filter: %{tags: ["production"], tag_operator: :or}
        })

      assert targeted_device_ids(runner) == [device.id]
    end
  end

  describe "tag operators" do
    test "both are offered, with the wording the deployment group form uses" do
      assert ScriptRunner.tag_operators() == [:and, :or]
      assert ScriptRunner.tag_operator_label(:and) == "Require all"
      assert ScriptRunner.tag_operator_label(:or) == "Allow any"
    end

    test "there is no default, so the UI must ask", ctx do
      _device = device(ctx, %{tags: ["production"]})

      {:error, changeset} = create(ctx, %{filter_type: :tags, filter: %{tags: ["production"]}})

      refute Ecto.Changeset.get_field(changeset, :filter).tag_operator,
             "a default here would mean the form could silently submit one"
    end
  end

  describe "connected_device_ids/1" do
    test "only a device whose latest connection is connected counts as online", ctx do
      connected = device(ctx)
      disconnected = device(ctx)
      never_connected = device(ctx)

      _ = Fixtures.device_connection_fixture(connected)
      _ = Fixtures.device_connection_fixture(disconnected, %{status: :disconnected})

      ids = [connected.id, disconnected.id, never_connected.id]

      assert ScriptRunners.connected_device_ids(ids) == [connected.id]
    end

    test "a connecting device is not yet online", ctx do
      connecting = device(ctx)
      _ = Fixtures.device_connection_fixture(connecting, %{status: :connecting})

      assert ScriptRunners.connected_device_ids([connecting.id]) == []
    end
  end

  describe "claim_pending_devices/2" do
    setup ctx do
      devices = for _ <- 1..5, do: device(ctx, %{tags: ["production"]})

      {:ok, runner, []} =
        create(ctx, %{filter_type: :tags, filter: %{tags: ["production"], tag_operator: :or}})

      %{runner: runner, devices: devices}
    end

    test "takes up to the limit and flips them to running", ctx do
      claimed = ScriptRunners.claim_pending_devices(ctx.runner.id, 2)

      assert length(claimed) == 2
      assert ScriptRunners.status_counts(ctx.runner) == %{running: 2, pending: 3}

      for result <- ScriptRunners.device_results(ctx.runner), result.device_id in claimed do
        assert result.status == :running
        assert result.started_at
      end
    end

    test "never hands the same device to two callers", ctx do
      first = ScriptRunners.claim_pending_devices(ctx.runner.id, 3)
      second = ScriptRunners.claim_pending_devices(ctx.runner.id, 3)

      # A retry racing the original dispatch must not run the script twice on one
      # device.
      assert first -- second == first
      assert length(first) == 3
      assert length(second) == 2
      assert Enum.sort(first ++ second) == Enum.sort(Enum.map(ctx.devices, & &1.id))
    end

    test "returns nothing once every device is claimed", ctx do
      _ = ScriptRunners.claim_pending_devices(ctx.runner.id, 5)

      assert ScriptRunners.claim_pending_devices(ctx.runner.id, 5) == []
    end

    test "a limit of zero or less claims nothing", ctx do
      assert ScriptRunners.claim_pending_devices(ctx.runner.id, 0) == []
      assert ScriptRunners.claim_pending_devices(ctx.runner.id, -3) == []
      assert ScriptRunners.status_counts(ctx.runner) == %{pending: 5}
    end
  end

  describe "counting work" do
    test "active_run_count counts unfinished runs, and never returns zero", ctx do
      # It divides the concurrency budget, so zero would be a division by zero.
      assert ScriptRunners.active_run_count() == 1

      _device = device(ctx, %{tags: ["production"]})

      {:ok, first, []} =
        create(ctx, %{filter_type: :tags, filter: %{tags: ["production"], tag_operator: :or}})

      {:ok, _second, []} =
        create(ctx, %{filter_type: :tags, filter: %{tags: ["production"], tag_operator: :or}})

      assert ScriptRunners.active_run_count() == 2

      {:ok, _first} = ScriptRunners.mark_finished(first)

      assert ScriptRunners.active_run_count() == 1
    end

    test "unfinished and pending counts track a device through its statuses", ctx do
      [one, two] = for _ <- 1..2, do: device(ctx, %{tags: ["production"]})

      {:ok, runner, []} =
        create(ctx, %{filter_type: :tags, filter: %{tags: ["production"], tag_operator: :or}})

      assert ScriptRunners.unfinished_device_count(runner.id) == 2
      assert ScriptRunners.pending_device_count(runner.id) == 2

      _ = ScriptRunners.claim_pending_devices(runner.id, 1)

      assert ScriptRunners.unfinished_device_count(runner.id) == 2
      assert ScriptRunners.pending_device_count(runner.id) == 1

      _ = ScriptRunners.record_device_result(runner.id, one.id, :completed, "done")
      _ = ScriptRunners.record_device_result(runner.id, two.id, :offline, nil)

      assert ScriptRunners.unfinished_device_count(runner.id) == 0
      assert ScriptRunners.pending_device_count(runner.id) == 0
    end
  end

  describe "release_stale_devices/2" do
    setup ctx do
      _devices = for _ <- 1..2, do: device(ctx, %{tags: ["production"]})

      {:ok, runner, []} =
        create(ctx, %{filter_type: :tags, filter: %{tags: ["production"], tag_operator: :or}})

      %{runner: runner}
    end

    test "puts a device stuck running back in the queue", ctx do
      claimed = ScriptRunners.claim_pending_devices(ctx.runner.id, 2)

      # Backdate the claim, standing in for a node that died holding these rows.
      Repo.update_all(
        from(srd in ScriptRunnerDevice, where: srd.script_runner_id == ^ctx.runner.id),
        set: [started_at: DateTime.add(DateTime.utc_now(), -10, :minute)]
      )

      assert ScriptRunners.release_stale_devices(ctx.runner.id) == 2
      assert ScriptRunners.status_counts(ctx.runner) == %{pending: 2}

      # Released means claimable again, which is what lets another node finish the
      # run rather than it stalling forever.
      assert Enum.sort(ScriptRunners.claim_pending_devices(ctx.runner.id, 2)) == Enum.sort(claimed)
    end

    test "leaves a device that is genuinely mid-script alone", ctx do
      _ = ScriptRunners.claim_pending_devices(ctx.runner.id, 2)

      assert ScriptRunners.release_stale_devices(ctx.runner.id) == 0
      assert ScriptRunners.status_counts(ctx.runner) == %{running: 2}
    end

    test "leaves devices that already answered alone", ctx do
      [result | _] = ScriptRunners.device_results(ctx.runner)
      _ = ScriptRunners.record_device_result(ctx.runner.id, result.device_id, :completed, "done")

      assert ScriptRunners.release_stale_devices(ctx.runner.id) == 0
      assert ScriptRunners.status_counts(ctx.runner)[:completed] == 1
    end
  end
end
