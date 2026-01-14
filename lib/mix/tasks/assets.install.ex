defmodule Mix.Tasks.Assets.Install do
  @shortdoc "Install web assets"
  @moduledoc false

  use Mix.Task

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
