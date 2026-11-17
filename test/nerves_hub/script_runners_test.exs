defmodule NervesHub.ScriptRunnersTest do
  use NervesHub.DataCase, async: true
  use Mimic

  alias NervesHub.AuditLogs
  alias NervesHub.Fixtures
  alias NervesHub.ScriptRunners
  alias NervesHub.ScriptRunners.ScriptRunner
  alias NervesHub.ScriptRunners.ScriptRunnerDevice
  alias NervesHub.Workers.ScriptRunnerDevice, as: ScriptRunnerDeviceWorker
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

  # A run's name is unique within its product, so the default is unique per call.
  # A test that cares about the name passes its own.
  defp create(ctx, params) do
    defaults = %{name: "Say hi #{System.unique_integer([:positive])}", text: "IO.puts(:hi)"}

    ScriptRunners.create(ctx.product, ctx.user, Map.merge(defaults, params))
  end

  defp targeted_device_ids(runner) do
    runner
    |> ScriptRunners.device_results()
    |> Enum.map(& &1.device_id)
    |> Enum.sort()
  end

  # The filter most of the tests below use, where the tags are not the point.
  defp tag_filter(), do: %{tags: ["production"], tag_operator: :or}

  # Counted straight from the table rather than through the context: these tests
  # are about rows surviving or not surviving a delete.
  defp device_row_count(runner_id) do
    ScriptRunnerDevice
    |> where([srd], srd.script_runner_id == ^runner_id)
    |> Repo.aggregate(:count)
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

    # Deliberate, and worth stating: targeting is exact, so `production` does not
    # reach a device tagged `Production`. Matching loosely would send a script to
    # devices the operator did not name.
    test "a tag is matched exactly, including its case", ctx do
      _upper = device(ctx, %{tags: ["Production"]})

      assert {:error, :no_devices} =
               create(ctx, %{filter_type: :tags, filter: %{tags: ["production"], tag_operator: :or}})
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

  # Both guarantees below hold for every filter type because `targetable_devices/1`
  # applies them to all three. Each is asserted per filter rather than once: the
  # filters are separate `resolve_targets/3` clauses, and one rewritten without the
  # base query would run an operator's script on a fleet they cannot see — with the
  # suite still green if only the tags path were covered.
  describe "create/3 scoping" do
    test "tags never target another product's devices", ctx do
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

    test "tags never target a soft deleted device", ctx do
      kept = device(ctx, %{tags: ["production"]})
      deleted = device(ctx, %{tags: ["production"]})

      {:ok, _deleted} = NervesHub.Repo.soft_delete(deleted)

      {:ok, runner, []} =
        create(ctx, %{filter_type: :tags, filter: %{tags: ["production"], tag_operator: :or}})

      assert targeted_device_ids(runner) == [kept.id]
    end

    # Naming a device outright is the filter most likely to reach across a product
    # boundary, since an operator can paste any identifier at all.
    test "identifiers never target another product's device, even when named", ctx do
      other_product = Fixtures.product_fixture(ctx.user, ctx.org, %{name: "other-by-identifier"})
      other_key = Fixtures.org_key_fixture(ctx.org, ctx.user)
      other_firmware = Fixtures.firmware_fixture(other_key, other_product)

      mine = device(ctx)
      theirs = Fixtures.device_fixture(ctx.org, other_product, other_firmware)

      {:ok, runner, unmatched} =
        create(ctx, %{
          filter_type: :identifiers,
          filter: %{identifiers: "#{mine.identifier},#{theirs.identifier}"}
        })

      assert targeted_device_ids(runner) == [mine.id]

      assert unmatched == [theirs.identifier],
             "a device outside the product is as good as nonexistent, and is reported that way"
    end

    test "identifiers never target a soft deleted device, even when named", ctx do
      kept = device(ctx)
      deleted = device(ctx)

      {:ok, _deleted} = NervesHub.Repo.soft_delete(deleted)

      {:ok, runner, unmatched} =
        create(ctx, %{
          filter_type: :identifiers,
          filter: %{identifiers: "#{kept.identifier},#{deleted.identifier}"}
        })

      assert targeted_device_ids(runner) == [kept.id]
      assert unmatched == [deleted.identifier]
    end

    test "deployment groups never target a soft deleted device", ctx do
      group = Fixtures.deployment_group_fixture(ctx.firmware, %{name: "group", user: ctx.user})

      kept = device(ctx, %{deployment_id: group.id})
      deleted = device(ctx, %{deployment_id: group.id})

      {:ok, _deleted} = NervesHub.Repo.soft_delete(deleted)

      {:ok, runner, []} =
        create(ctx, %{filter_type: :deployment_groups, filter: %{deployment_group_ids: [group.id]}})

      assert targeted_device_ids(runner) == [kept.id]
    end

    test "deployment groups never reach another product's group", ctx do
      other_product = Fixtures.product_fixture(ctx.user, ctx.org, %{name: "other-by-group"})
      other_key = Fixtures.org_key_fixture(ctx.org, ctx.user)
      other_firmware = Fixtures.firmware_fixture(other_key, other_product)

      their_group = Fixtures.deployment_group_fixture(other_firmware, %{name: "theirs", user: ctx.user})
      _theirs = Fixtures.device_fixture(ctx.org, other_product, other_firmware, %{deployment_id: their_group.id})

      # A device of our own, so the run failing is about the group rather than the
      # product having nothing in it.
      _mine = device(ctx)

      assert {:error, :no_devices} =
               create(ctx, %{
                 filter_type: :deployment_groups,
                 filter: %{deployment_group_ids: [their_group.id]}
               })
    end

    test "a deployment group that does not exist targets nothing", ctx do
      _mine = device(ctx)

      assert {:error, :no_devices} =
               create(ctx, %{filter_type: :deployment_groups, filter: %{deployment_group_ids: [0]}})
    end
  end

  describe "create/3 validation" do
    test "refuses a run that would target nothing, and enqueues no work", ctx do
      assert {:error, :no_devices} =
               create(ctx, %{filter_type: :tags, filter: %{tags: ["nobody-has-this"], tag_operator: :or}})

      refute_enqueued(worker: ScriptRunnerDispatch)
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

    test "refuses script text over 64 KB", ctx do
      _device = device(ctx, %{tags: ["production"]})

      params = %{filter_type: :tags, filter: %{tags: ["production"], tag_operator: :or}}

      assert {:error, changeset} = create(ctx, Map.put(params, :text, String.duplicate("a", 65_537)))
      assert Enum.any?(errors_on(changeset).text, &(&1 =~ "should be at most"))

      assert {:ok, _runner, []} =
               create(ctx, Map.merge(params, %{name: "At the cap", text: String.duplicate("a", 65_536)}))
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

    test "audits the run against the product", ctx do
      _device = device(ctx, %{tags: ["production"]})

      {:ok, runner, []} =
        create(ctx, %{filter_type: :tags, filter: %{tags: ["production"], tag_operator: :or}})

      logs = AuditLogs.logs_for(ctx.product)

      assert Enum.any?(logs, fn log ->
               log.description =~ "ran a script named #{runner.name} with id #{runner.id} on 1 devices"
             end)
    end
  end

  describe "unique names" do
    test "two runs in a product cannot share a name", ctx do
      _device = device(ctx, %{tags: ["production"]})

      {:ok, _first, []} = create(ctx, %{name: "Reboot", filter_type: :tags, filter: tag_filter()})

      {:error, changeset} = create(ctx, %{name: "Reboot", filter_type: :tags, filter: tag_filter()})

      assert "has already been used by another run in this product" in errors_on(changeset).name
    end

    # Names are scoped to the product, the way deployment group and support script
    # names are.
    test "two products can each have a run with the same name", ctx do
      _device = device(ctx, %{tags: ["production"]})

      other_product = Fixtures.product_fixture(ctx.user, ctx.org, %{name: "Elsewhere"})
      other_key = Fixtures.org_key_fixture(ctx.org, ctx.user)
      other_firmware = Fixtures.firmware_fixture(other_key, other_product)
      _other_device = Fixtures.device_fixture(ctx.org, other_product, other_firmware, %{tags: ["production"]})

      {:ok, _first, []} = create(ctx, %{name: "Reboot", filter_type: :tags, filter: tag_filter()})

      assert {:ok, _second, []} =
               ScriptRunners.create(other_product, ctx.user, %{
                 name: "Reboot",
                 text: "IO.puts(:hi)",
                 filter_type: :tags,
                 filter: tag_filter()
               })
    end
  end

  describe "rerun/3" do
    test "a run that has not finished cannot be rerun", ctx do
      _device = device(ctx, %{tags: ["production"]})
      {:ok, pending, []} = create(ctx, %{name: "Reboot", filter_type: :tags, filter: tag_filter()})
      {:ok, running} = ScriptRunners.mark_running(pending)

      assert {:error, :not_completed} = ScriptRunners.rerun(ctx.product, ctx.user, pending)
      assert {:error, :not_completed} = ScriptRunners.rerun(ctx.product, ctx.user, running)

      assert [_only_the_original] = ScriptRunners.all_by_product(ctx.product)
    end

    test "the copy is named after the original, and says where it came from", ctx do
      _device = device(ctx, %{tags: ["production"]})

      {:ok, original, []} = create(ctx, %{name: "Reboot", filter_type: :tags, filter: tag_filter()})

      {:ok, copy, []} = ScriptRunners.rerun(ctx.product, ctx.user, finished(original))

      assert copy.name == "Reboot copy 1"
      assert copy.description == "copied from Reboot"
    end

    # The original's description is as relevant to the copy as its code is, so the
    # note goes below it rather than over it.
    test "an existing description is kept above the copied-from note", ctx do
      _device = device(ctx, %{tags: ["production"]})

      {:ok, original, []} =
        create(ctx, %{name: "Reboot", description: "Modem check", filter_type: :tags, filter: tag_filter()})

      {:ok, copy, []} = ScriptRunners.rerun(ctx.product, ctx.user, finished(original))

      assert copy.description == "Modem check\ncopied from Reboot"
    end

    test "the copy number climbs as the same run is rerun again", ctx do
      _device = device(ctx, %{tags: ["production"]})

      {:ok, original, []} = create(ctx, %{name: "Reboot", filter_type: :tags, filter: tag_filter()})

      {:ok, first, []} = ScriptRunners.rerun(ctx.product, ctx.user, finished(original))
      {:ok, second, []} = ScriptRunners.rerun(ctx.product, ctx.user, finished(original))
      {:ok, third, []} = ScriptRunners.rerun(ctx.product, ctx.user, finished(original))

      assert first.name == "Reboot copy 1"
      assert second.name == "Reboot copy 2"
      assert third.name == "Reboot copy 3"
    end

    # Otherwise rerunning a rerun would read "Reboot copy 1 copy 1".
    test "rerunning a copy keeps the base name rather than nesting suffixes", ctx do
      _device = device(ctx, %{tags: ["production"]})

      {:ok, original, []} = create(ctx, %{name: "Reboot", filter_type: :tags, filter: tag_filter()})

      {:ok, first, []} = ScriptRunners.rerun(ctx.product, ctx.user, finished(original))
      {:ok, second, []} = ScriptRunners.rerun(ctx.product, ctx.user, finished(first))

      assert second.name == "Reboot copy 2"
      # The note names the run it was actually copied from, which was the copy.
      assert second.description =~ "copied from Reboot copy 1"
    end

    test "a name already taken by an unrelated run is skipped", ctx do
      _device = device(ctx, %{tags: ["production"]})

      {:ok, original, []} = create(ctx, %{name: "Reboot", filter_type: :tags, filter: tag_filter()})

      # Someone named a run by hand exactly what the first copy would have been.
      {:ok, _squatter, []} = create(ctx, %{name: "Reboot copy 1", filter_type: :tags, filter: tag_filter()})

      {:ok, copy, []} = ScriptRunners.rerun(ctx.product, ctx.user, finished(original))

      assert copy.name == "Reboot copy 2"
    end

    # `%` and `_` are LIKE wildcards, and the name is operator-supplied.
    test "a name holding LIKE wildcards is matched literally", ctx do
      _device = device(ctx, %{tags: ["production"]})

      {:ok, original, []} = create(ctx, %{name: "100% _done", filter_type: :tags, filter: tag_filter()})

      # Would be matched by an unescaped "100% _done copy %" pattern, and would
      # push the real copy to number 2.
      {:ok, _decoy, []} = create(ctx, %{name: "100XX Ydone copy 1", filter_type: :tags, filter: tag_filter()})

      {:ok, copy, []} = ScriptRunners.rerun(ctx.product, ctx.user, finished(original))

      assert copy.name == "100% _done copy 1"
    end

    # Two reruns of one run can both pick the same free `copy N`. A concurrent
    # rerun cannot be interleaved inside one sandbox transaction, so the rival is
    # inserted from inside the rerun's own changeset build: after the free name is
    # chosen, before the insert that needs it.
    test "a rerun that loses the race for its name takes the next one", ctx do
      _device = device(ctx, %{tags: ["production"]})
      {:ok, original, []} = create(ctx, %{name: "Reboot", filter_type: :tags, filter: tag_filter()})

      win_races(1)

      {:ok, copy, []} = ScriptRunners.rerun(ctx.product, ctx.user, finished(original))

      assert copy.name == "Reboot copy 2"
    end

    test "a rerun that loses the race twice reports it rather than trying again", ctx do
      _device = device(ctx, %{tags: ["production"]})
      {:ok, original, []} = create(ctx, %{name: "Reboot", filter_type: :tags, filter: tag_filter()})

      win_races(2)

      assert {:error, changeset} = ScriptRunners.rerun(ctx.product, ctx.user, finished(original))
      assert "has already been used by another run in this product" in errors_on(changeset).name
    end
  end

  # Only a finished run can be rerun.
  defp finished(%ScriptRunner{status: :completed} = run), do: run

  defp finished(run) do
    {:ok, run} = ScriptRunners.mark_finished(run)
    run
  end

  # For the next `count` runs built, a rival run takes the chosen name first.
  defp win_races(count) do
    Process.put(:races_left, count)

    stub(ScriptRunner, :create_changeset, fn product, user, params ->
      left = Process.get(:races_left)

      if left > 0 do
        Process.put(:races_left, left - 1)

        rival = %{name: params.name, text: "IO.puts(:rival)", filter_type: :tags, filter: tag_filter()}
        Repo.insert!(call_original(ScriptRunner, :create_changeset, [product, user, rival]))
      end

      call_original(ScriptRunner, :create_changeset, [product, user, params])
    end)
  end

  describe "delete/3" do
    test "another run's device rows are left alone", ctx do
      for _ <- 1..2, do: device(ctx, %{tags: ["production"]})

      {:ok, doomed, []} = create(ctx, %{filter_type: :tags, filter: tag_filter()})
      {:ok, kept, []} = create(ctx, %{filter_type: :tags, filter: tag_filter()})

      {:ok, _deleted} = ScriptRunners.delete(doomed, ctx.user, ctx.product)

      assert device_row_count(kept.id) == 2
    end

    # A device job left queued for a deleted run has nothing left to do, so it is
    # cancelled with the run rather than left to start and find the run gone.
    test "the run's queued device jobs are cancelled, and another run's are not", ctx do
      for _ <- 1..2, do: device(ctx, %{tags: ["production"]})

      {:ok, doomed, []} = create(ctx, %{filter_type: :tags, filter: tag_filter()})
      {:ok, kept, []} = create(ctx, %{filter_type: :tags, filter: tag_filter()})

      for runner <- [doomed, kept] do
        assert {:snooze, _} = perform_job(ScriptRunnerDispatch, %{"script_runner_id" => runner.id})
      end

      {:ok, _deleted} = ScriptRunners.delete(doomed, ctx.user, ctx.product)

      remaining = Enum.map(all_enqueued(worker: ScriptRunnerDeviceWorker), & &1.args["script_runner_id"])

      assert remaining == [kept.id, kept.id]
    end

    test "the deletion is recorded in the audit log", ctx do
      _device = device(ctx, %{tags: ["production"]})

      {:ok, runner, []} = create(ctx, %{name: "Reboot", filter_type: :tags, filter: tag_filter()})

      {:ok, _deleted} = ScriptRunners.delete(runner, ctx.user, ctx.product)

      descriptions = Enum.map(AuditLogs.logs_for(ctx.product), & &1.description)

      assert Enum.any?(descriptions, &(&1 =~ "deleted the script run named Reboot"))
    end
  end

  # The controller cannot choose the page size, so paging across several queries
  # is exercised here; the CSV itself is covered by the export tests in
  # `NervesHubWeb.Live.ScriptRunsTest`.
  describe "export_reducer/4" do
    defp collect_rows(runner, opts) do
      {:ok, rows} = ScriptRunners.export_reducer(runner, [], fn acc, row -> {:ok, [row | acc]} end, opts)

      Enum.reverse(rows)
    end

    test "reads every row exactly once, in identifier order, across pages", ctx do
      devices = for _i <- 1..5, do: device(ctx, %{tags: ["production"]})

      {:ok, runner, []} = create(ctx, %{filter_type: :tags, filter: tag_filter()})

      identifiers = Enum.map(collect_rows(runner, page_size: 2), &hd/1)

      assert identifiers == devices |> Enum.map(& &1.identifier) |> Enum.sort()
    end

    # A run whose size is an exact multiple of the page size ends on a full page,
    # and the empty page after it must end the export rather than loop.
    test "ends cleanly when the last page is full", ctx do
      for _i <- 1..4, do: device(ctx, %{tags: ["production"]})

      {:ok, runner, []} = create(ctx, %{filter_type: :tags, filter: tag_filter()})

      assert length(collect_rows(runner, page_size: 2)) == 4
    end

    # A client that went away mid-download stops the export, rather than the rest
    # of the run's pages being read for nobody.
    test "stops reading once the callback returns an error", ctx do
      for _i <- 1..5, do: device(ctx, %{tags: ["production"]})

      {:ok, runner, []} = create(ctx, %{filter_type: :tags, filter: tag_filter()})

      {:ok, seen} =
        ScriptRunners.export_reducer(
          runner,
          0,
          fn
            2, _row -> {:error, :closed}
            seen, _row -> {:ok, seen + 1}
          end,
          page_size: 2
        )

      assert seen == 2
    end

    # Each page is its own query, not one long-held transaction: a slow client
    # must not keep a connection checked out for the whole download.
    test "does not wrap the export in a transaction", ctx do
      _device = device(ctx, %{tags: ["production"]})

      {:ok, runner, []} = create(ctx, %{filter_type: :tags, filter: tag_filter()})

      {:ok, in_transaction?} =
        ScriptRunners.export_reducer(runner, nil, fn _acc, _row -> {:ok, Repo.in_transaction?()} end)

      refute in_transaction?
    end
  end
end
