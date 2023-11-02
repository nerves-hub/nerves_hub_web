defmodule NervesHub.Config.FirmwareBackendFile do
  use Vapor.Planner

  dotenv()

  config :firmware_backend,
         env([
           {:local_path, "FIRMWARE_LOCAL_PATH"},
           {:public_path, "FIRMWARE_PUBLIC_PATH"}
         ])
end
