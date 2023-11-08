defmodule NervesHub.Config.DNSPoll do
  use Vapor.Planner

  dotenv()

  config :dns_poll,
         env([
           {:polling_interval, "LIBCLUSTER_DNSPOLL_POLLING_INTERVAL",
            default: 5000, map: &String.to_integer/1},
           {:query, "LIBCLUSTER_DNSPOLL_QUERY"},
           {:node_basename, "LIBCLUSTER_DNSPOLL_NODE_BASENAME"}
         ])
end
