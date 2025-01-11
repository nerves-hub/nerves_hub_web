defmodule Mix.Tasks.Assets.Install do
  @moduledoc false

  use Mix.Task

  @shortdoc "Install web assets"
  @assets Path.expand("../../../assets", __DIR__)

  def run(_) do
    System.cmd(
      "npm",
      ["install"],
      cd: @assets,
      stderr_to_stdout: true,
      into: IO.stream(:stdio, :line),
      env: []
    )
  end
end
