defmodule NervesHub.RateLimit.LogLines do
  use Hammer, backend: :atomic, algorithm: :token_bucket
end
