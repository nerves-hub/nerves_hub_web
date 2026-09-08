defmodule NervesHub.Scripts.ScriptTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Fixtures
  alias NervesHub.Scripts.Script

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    %{user: user, product: product}
  end

  test "update_changeset/3 returns a valid changeset", %{user: user, product: product} do
    script = %Script{name: "old name", text: "echo hello", product_id: product.id, created_by_id: user.id}

    changeset = Script.update_changeset(script, user, %{name: "new name", text: "echo world"})
    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :name) == "new name"
    assert changeset.changes[:last_updated_by_id] == user.id
  end

  test "update_changeset/3 with missing required fields is invalid", %{user: user} do
    script = %Script{name: "old name", text: "echo hello"}
    changeset = Script.update_changeset(script, user, %{name: ""})
    refute changeset.valid?
  end

  describe "language" do
    test "defaults to Elixir" do
      changeset = Script.validate_changeset(%{name: "a script", text: "Foo.bar()"})

      assert changeset.valid?
      assert Ecto.Changeset.apply_changes(changeset).language == :elixir
    end

    test "accepts shell" do
      changeset = Script.validate_changeset(%{name: "a script", text: "echo hi", language: "shell"})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :language) == :shell
    end

    test "rejects an unknown language" do
      changeset = Script.validate_changeset(%{name: "a script", text: "echo hi", language: "brainfuck"})

      refute changeset.valid?
      # Not `errors_on/1`: an Ecto.Enum cast error carries the parameterized
      # type in its metadata, which that helper cannot interpolate.
      assert {"is invalid", _} = changeset.errors[:language]
    end
  end

  describe "Elixir syntax validation" do
    test "accepts valid Elixir" do
      changeset = Script.validate_changeset(%{name: "a script", text: "NervesMOTD.print()"})

      assert changeset.valid?
    end

    test "reports the position and the reason" do
      changeset = Script.validate_changeset(%{name: "a script", text: "if true do"})

      refute changeset.valid?

      assert "has invalid Elixir syntax at line 1, column 9: missing terminator: end" in errors_on(changeset).text
    end

    # The parser answers with a two part `{prefix, suffix}` message for these
    # rather than a plain string, which is easy to mishandle. Deleting the line
    # that opened a block is enough to produce one.
    test "reports errors whose message arrives in two parts" do
      changeset = Script.validate_changeset(%{name: "a script", text: "end"})

      refute changeset.valid?

      assert "has invalid Elixir syntax at line 1, column 1: unexpected reserved word: end" in errors_on(changeset).text
    end

    test "reports an incomplete expression" do
      changeset = Script.validate_changeset(%{name: "a script", text: "1 +"})

      refute changeset.valid?

      assert "has invalid Elixir syntax at line 1, column 3: syntax error: expression is incomplete" in errors_on(
               changeset
             ).text
    end

    test "reports a mismatched delimiter" do
      changeset = Script.validate_changeset(%{name: "a script", text: "[1, 2}"})

      refute changeset.valid?
      assert ["has invalid Elixir syntax at line 1, column 1: unexpected token: }"] = errors_on(changeset).text
    end

    test "does not add identifiers from the script to the atom table" do
      refute Enum.any?(
               ["a_support_script_identifier", "Elixir.ASupportScriptAlias"],
               &atom_exists?/1
             )

      changeset =
        Script.validate_changeset(%{
          name: "a script",
          text: "a_support_script_identifier = ASupportScriptAlias"
        })

      assert changeset.valid?

      refute Enum.any?(
               ["a_support_script_identifier", "Elixir.ASupportScriptAlias"],
               &atom_exists?/1
             )
    end

    test "does not run for shell scripts" do
      changeset =
        Script.validate_changeset(%{
          name: "a script",
          text: "if [ -f /tmp/x ]; then echo yes; fi",
          language: "shell"
        })

      assert changeset.valid?
    end

    test "runs when a shell script is switched back to Elixir" do
      script = %Script{name: "a script", text: "echo hi", language: :shell}

      changeset = Script.validate_changeset(script, %{text: "if true do", language: "elixir"})

      refute changeset.valid?
    end
  end

  defp atom_exists?(name) do
    _ = String.to_existing_atom(name)
    true
  rescue
    ArgumentError -> false
  end
end
