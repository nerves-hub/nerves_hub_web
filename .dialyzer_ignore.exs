[
  {"lib/x509/certificate.ex", :unknown_type},
  {"lib/x509/certificate/extension.ex", :unknown_type},
  {"lib/nerves_hub/analytics_repo.ex", :contract_supertype},
  # Ecto.Multi.t() opaque type false positives — MapSet.new() returns a concrete
  # %MapSet{map: %{}} that Dialyzer can't unify with the opaque MapSet.internal(_) type,
  # causing spurious call_without_opaque warnings on Ecto.Multi pipe chains.
  {"lib/nerves_hub/accounts.ex", :call_without_opaque},
  {"lib/nerves_hub/accounts/remove_account.ex", :call_without_opaque},
  {"lib/nerves_hub/devices.ex", :call_without_opaque}
]
