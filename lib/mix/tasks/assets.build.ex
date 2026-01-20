defmodule Mix.Tasks.Assets.Build do
  @shortdoc "Build web assets"
  @moduledoc false

  use Mix.Task

  @assets Path.expand("../../../assets", __DIR__)

  def run(_) do
    System.cmd(
      "npm",
      ["run", "deploy"],
      cd: @assets,
      stderr_to_stdout: true,
      into: IO.stream(:stdio, :line),
      env: []
    )
  end
end
