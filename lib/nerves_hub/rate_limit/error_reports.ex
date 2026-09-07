defmodule NervesHub.RateLimit.ErrorReports do
  use Hammer, backend: :atomic, algorithm: :token_bucket
end
