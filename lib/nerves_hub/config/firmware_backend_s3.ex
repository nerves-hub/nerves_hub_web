defmodule NervesHub.Config.FirmwareBackendS3 do
  use Vapor.Planner

  dotenv()

  config :firmware_backend,
         env([
           {:access_key_id, "AWS_ACCESS_KEY_ID"},
           {:secret_access_key, "AWS_SECRET_ACCESS_KEY"},
           {:region, "AWS_REGION"},
           {:bucket, "AWS_FIRMWARE_BUCKET"}
         ])
end
