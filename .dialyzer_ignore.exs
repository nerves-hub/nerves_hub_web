[
  {"lib/x509/certificate.ex", :unknown_type},
  {"lib/x509/certificate/extension.ex", :unknown_type},
  {"lib/nerves_hub/analytics_repo.ex", :contract_supertype},
  # Ecto.Multi.t() opaque type false positives — MapSet.new() returns a concrete
  # %MapSet{map: %{}} that Dialyzer can't unify with the opaque MapSet.internal(_) type,
  # causing spurious call_without_opaque warnings on Ecto.Multi pipe chains.
  {"lib/nerves_hub/accounts.ex", :call_without_opaque},
  {"lib/nerves_hub/accounts/remove_account.ex", :call_without_opaque},
  {"lib/nerves_hub/devices.ex", :call_without_opaque},
  {"lib/nerves_hub/devices/network_identities.ex", :call_without_opaque},
  {"lib/nerves_hub/devices/alarms.ex", :call_without_opaque},
  {"lib/nerves_hub/devices/updates.ex", :call_without_opaque},
  {"lib/nerves_hub/products.ex", :call_without_opaque},
  {"lib/nerves_hub/products/health_profiles.ex", :call_without_opaque},
  # `Mint.WebSocket.t()` is opaque: its success typing returns the concrete
  # struct, which Dialyzer won't match against the opaque type at a call site,
  # so it drops the `{:ok, conn, websocket}` result of `Mint.WebSocket.new/4`
  # and says the pattern can never match. Any caller gets it; the upgrade
  # succeeds, as the Socket Mode tests show.
  {"lib/nerves_hub_web/integrations/slack/socket.ex", :pattern_match},
  {"lib/nerves_hub_web/components/layouts.ex", :call},
  {"lib/nerves_hub_web/components/layouts.ex", :no_return}
]
