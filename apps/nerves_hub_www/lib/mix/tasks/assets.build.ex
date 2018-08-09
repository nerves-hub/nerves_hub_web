defmodule Mix.Tasks.Assets.Build do
  use Mix.Task

  @shortdoc "Build web assets"
  @assets Path.expand("../../../assets", __DIR__)

  def run(_) do
    System.cmd(
      "yarn",
      ["build"],
      cd: @assets,
      stderr_to_stdout: true,
      into: IO.stream(:stdio, :line)
    )
  end
end
