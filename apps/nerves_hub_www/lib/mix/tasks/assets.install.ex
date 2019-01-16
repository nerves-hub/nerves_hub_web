defmodule Mix.Tasks.Assets.Install do
  use Mix.Task

  @shortdoc "Install web assets"
  @assets Path.expand("../../../assets", __DIR__)

  def run(_) do
    System.cmd(
      "yarn",
      ["install"],
      cd: @assets,
      stderr_to_stdout: true,
      into: IO.stream(:stdio, :line)
    )
  end
end
