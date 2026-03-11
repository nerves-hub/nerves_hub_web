# Changelog

## v2.4.0

This release comes with the discovery of CVE-2026-28806. During routine development we noticed lacking authorization checks for device bulk actions. Investigating it we found that it did allow a user to take actions on devices outside of their organization by manipulating the client-side of the application. As part of this we also discovered an API endpoint that exposed an equivalent privilege escalation and ability to escape the scope.

If you run NervesHub for only your organization this issue may not affect you at all or would likely have low impact. It is privilege escalation and a tenancy violation. This is significantly more important to a multi-organization system such as NervesCloud. You should still update immediately since this may give unintended access to people in your organization.

The bulk action issue goes back to 2021 and is present in NervesHub 1.x as far back as bulk actions have existed. The API issue is more recent during a rework of the API endpoints. Details are in the CVE references.

Of course this has made us look very carefully at the structure of authorization and access in NervesHub. What we found was a lack of structure which increases the risk of introducing issues like this. In preparation for the CVE fixes we introduced a scoping mechanism to have a consistent way of passing around authorization scopes. This makes it more obvious when authorization is being checked and reduces the risk of introducing new issues. We have branches and PRs in the wings for enforcing authorization checks in LiveViews and API endpoints. Those should land shortly as well.

We take security very seriously. Finding a serious problem is never fun. Not finding it is significantly worse. This was discovered by us, fixed by us and released by us. We are thankful to the Erlang Ecosystem Foundation's CNA for their great help in the CVE process. If you discover flaws in your Elixir project we highly encourage you to learn the correct process and the EEF CNA will help you through it.

### Themes

- **New UI Completion**: Removed old UI entirely, implemented remaining pages in the new design
- **Deployment Releases**: Improved release management significantly with new releases concept
- **Sentry Improvements**: Upgraded to Sentry 12, added opt-in logging and tracing support
- **Lucide Icons**: Added support for Lucide icon set
- **Device Network Info**: Store and display device network interface data, still needs work in `nerves_hub_link`
- **Code Quality**: Enforced Credo in CI, consolidated tests, removed dead code

### Added

- Add support for Lucide icons (#2524)
- Allow for Sentry tracing to be enabled, disabled by default (#2525)
- Support Sentry Logging as opt-in (#2522)
- Rollout options for deployments (#2441)
- Store device network interface data (#2437)
- Add default org and product when user registers (#2475)
- Add support for a 400 HTTP error page (#2471)
- Add a Signing Key format validation (#2511)
- Basic responsive web UI (#2517)

### Changed

- Move to using a `current_release` association on `DeploymentGroup` (#2490)
- Implement the rest of the new UI, basic edition (#2439)
- Move Account Tokens to `/account` and to the new UI (#2493)
- Remove new_ui config and ui switcher (#2488)
- Remove JS and CSS used by the old UI (#2494)
- Remove UI switch from the bad old days (#2456)
- Consolidate and remove duplicated UI tests (#2497)
- Firmware connected to Releases can't be deleted (#2462)
- Deployment Release improvements (#2453)
- Speed up Deployment Group queries which include device and release counts (#2485)
- When matching deployment groups with a device, prioritize matching tags (#2435)
- Filter out already running Orchestrators (#2470)
- Address an issue where all Orchestrators might be already running (#2474)
- Don't report Orchestrator `:already_started` errors (#2520)
- After updating a Deployment Group, preload the Firmware for later use (#2472)
- Update the various Firmware lists and drop downs when new Firmware is available (#2463)
- Stream firmware to file when updating (#2450)
- Reuse the tmp firmware file created by LiveView.Upload (#2500)
- Clean up after creating firmware deltas (#2442)
- Remove unused files in delta generation (#2446)
- Return `{:ok, delta}` if a delta already exists (#2481)
- Change orgs view to make it more obvious that products are shown (#2455)
- Only show Firmware flashes when viewing the Firmware list page (#2519)
- Move to using Phoenix Scopes for better auth organization (#2515)
- Fully embrace Phoenix layouts (#2521)
- Move the sidebar/no-sidebar layouts to their own heex files (#2526)
- Support alternative 'alive' http paths (#2527)
- Removed some unused code (thanks new Elixir compiler!) (#2530)
- Only fetch Org and Product if the user is logged in (#2531)
- Remove `handle_events` we don't use in the UI
- Disable the bulk action checkboxes if not authorized for `device:update`
- Use a decorator to reuse authorization logic
- Use the `current_scope` in all bulk action context calls
- Its better to unregister completed uploads vs cancelling (#2508)
- Switch to `Repo.transact` (#2467)
- Oban doesn't need its own Repo (#2464)
- Remove one last `ObanRepo` reference (#2503)
- Use more tmp dirs in tests, and use Briefly for delta generation (#2502)
- Use `:monotonic` with the unique integers we generate in our fixtures (#2504)
- Enforce Credo code quality (#2443)
- Make user auth play nice with Credo update (#2448)
- Use `get_field` when updating a deployment's status (#2452)
- Use updated Phoenix error page configs (#2478)
- Relax the regex for FWUP metadata parsing (#2459)
- Make sure the Orchestrator is notified when devices are added to it (#2461)
- Handle `UserSocket` auth token missing user cases (#2465)
- Show an error message if the location data sent by a device is invalid (#2473)
- Log when an empty message is received by `Extensions.LocalShell` (#2518)
- Log an error if `Connections.device_disconnected` returns an error (#2484)
- Add `join_ref`s to Channel messages missing a `join_ref` (#2506)
- Pin Phoenix to 1.8.2 to allow console channel to work (#2505)
- Update all Node deps, resolves a security warning with semver (#2510)
- Add `deployment_group_id` index to `deployment_releases` (#2483)
- Add some extra tests for Orchestrator Registration (#2479)
- Bump Elixir to 1.19.5 and OTP 28 (#2469)

### Fixed

- Fix CVE-2026-28806 by introducing scoped authorization for device bulk actions and API endpoints.
- Add access and permission checks to Device list bulk actions
- Address an issue with the Device API plug not scoping to the user
- Empty form recovery shouldn't show an error message
- Fix issue where device API listing failed due to missing preload (#2514)
- The Devices endpoint doesn't have access to verified routes (#2523)
- Fix 400 API errors, and improve the Device code API action (#2529)
- Use the correct error HTML view for the Devices endpoint (#2516)
- Fix a very hidden race condition related to finding devices to be updated (#2468)
- Fix matching device to deployment groups under specific conditions (#2436)
- Fix a pill overflow in deployment group firmware version (#2507)
- Fix clickable area of product in orgs list (#2454)
- Fix edit user button and a couple inefficient page-refresh nav links (#2451)
- Fix an error related to a password being nil (#2489)
- Fix a little Elixir warning with an old migration (#2492)
- Fixed the naming of the signing key tests file (#2477)
- Ignore `handle_async` result calls that bubble up to the live view (#2512)
- Update FWUP due to a broken zlib download (#2460)
- Update package.lock from recent asset changes (#2501)

### Dependencies

- **bandit**: 1.8.0 -> 1.10.3
- **briefly**: 0.5.1 (new)
- **castore**: 1.0.15 -> 1.0.17
- **ch**: 0.5.6 -> 0.7.1
- **confuse**: 0.2.1 -> 0.3.1
- **credo**: 1.7.13 -> 1.7.16
- **ecto**: 3.13.3 -> 3.13.5
- **ecto_ch**: 0.8.2 -> 0.8.6
- **ecto_sql**: 3.13.2 -> 3.13.4
- **ex_aws**: 2.5.11 -> 2.6.1
- **ex_aws_s3**: 2.5.8 -> 2.5.9
- **expo**: 1.1.0 -> 1.1.1
- **finch**: 0.20.0 -> 0.21.0
- **lucide**: 0.577.0 (new)
- **oban**: 2.20.1 -> 2.20.3
- **oban_met**: 1.0.3 -> 1.0.6
- **oban_web**: 2.11.4 -> 2.11.8
- **open_api_spex**: 3.22.0 -> 3.22.2
- **opentelemetry**: 1.6.0 -> 1.7.0
- **opentelemetry_api**: 1.4.1 -> 1.5.0
- **opentelemetry_exporter**: 1.9.0 -> 1.10.0
- **phoenix**: 1.8.1 -> 1.8.5
- **phoenix_ecto**: 4.6.5 -> 4.7.0
- **phoenix_live_view**: 1.1.13 -> 1.1.26
- **phoenix_test**: 0.8.1 -> 0.9.1
- **postgrex**: 0.21.1 -> 0.22.0
- **process_hub**: 0.3.3-alpha -> 0.5.0-beta
- **req**: 0.5.17 (new)
- **sentry**: 11.0.4 -> 12.0.2
- **slipstream**: 1.2.0 -> 1.2.2
- **slugify**: 1.3.1 (new)
- **swoosh**: 1.19.8 -> 1.22.1
- **tesla**: 1.14.1 -> 1.16.0
- **unzip**: 0.12.0 -> 0.13.0

## v2.3.0

### Themes

- **Extensions System**: Device channel extensions for health monitoring, logging, and local shell
- **Firmware Delta Updates**: Delta generation, delivery, tracking, and bandwidth savings
- **New UI**: Complete UI overhaul for devices, deployments, firmware and more
- **Deployment Orchestrator**: New orchestrator with better and more consistent behavior
- **Device Filtering**: Enhanced filtering by health metrics, deployment, tags, and update status
- **Device Connections & Performance**: Connection management, PubSub fastlaning, and query optimization
- **Support Scripts**: Script execution, tagging, tracking, and management
- **Device Priority & Pinning**: Device organization and prioritization
- **Health & Metrics**: Device health reporting, custom metrics, and chart improvements
- **Firmware Validation**: Tracking validation status and auto-revert detection
- **Authentication & Security**: Google login, token management revamp, and role-based permissions
- **Audit Logging**: Improved audit trail logging
- **Console Improvements**: Theater mode, upload notifications, and LiveView hooks
- **Deployment Groups**: Bulk operations, validation improvements, and form recovery
- **Performance & Scalability**: jemalloc, async loading, streaming queries, and batch operations
- **Telemetry & Monitoring**: Health checks, LiveDashboard metrics, Oban web, and OpenTelemetry
- **Device Location**: Custom location support and tracking
- **LiveView & Form Recovery**: Recoverable forms during connection issues
- **Code Quality & Tooling**: Quokka linting, Credo, spell checking, and Dialyzer in CI
- **Release History**: Track and display release history

### Added

- New UI for large parts of NervesHub
- Add a way to extend DeviceChannel functionality via Extensions (#1479)
- Hide disabled extensions in the UI (#1654)
- Check device api version before requesting extensions (#1668)
- Add filtering devices based on Health extension metrics
- Track release history (#2404)
- Add devices online/offline to org and product views (#2402)
- Add a new interactive Local Shell extension (#2378)
- Add preparation step for orchestrator doing firmware deltas (#2262)
- Add a firmware validation filter when checking which devices are available for updating (#2369)
- Support log event exclusions (#2361)
- Org settings: Firmware proxy URL (#2354)
- Add `Connected` and `Last Seen` to the Devices General Info box (#2347)
- Enable delta updates for new deployments (#2345)
- Track a device's firmware validation status, and if an auto-revert was detected (#2314)
- Implement logging of transfer savings from deltas with Postgres (#2295)
- Enable metrics in Phoenix LiveDashboard (#2385)
- Add Healthcheck Endpoint for Service Monitoring (#2248)
- Add information about available deltas to deployment summary (#2139)
- Enable firmware delta delivery (#2090)
- Device priority updates (#2103)
- Add tags to scripts (#2117)
- Support Devices sending log messages via a new Logging extension (#2080)
- Add support for Google login (#2061)
- Show users currently watching device page (#1947)
- Add a theater mode, pseudo-fullscreen to console (#1977)
- Filter devices without deployment (#1951)
- Pinned devices (#1897)
- Add device metric filtering support to the new UI (#1924)
- Add deployment filter for devices (#1914)
- Very basic health status report for device (#1805)
- Create audit log when archive is sent to device (#1847)
- Add support for clear and update deployment broadcasts (#1864)
- Add support for a custom defined device location (#1848)
- Save the device location to `DeviceConnection.metadata` (#1850)
- Track who created or edited script (#1838)
- Custom metrics when viewing device (#1804)
- Add fancy progress bar for devices list (#1791)
- Add Oban web for server introspection (#1774)
- Allow for custom `Archive` file size upload limits (#1754)
- Allow for the firmware file size limit to be configurable (#1746)
- Add a type to the `AuditLog` schema (#1730)
- Bulk move devices to deployment (#1718)
- Set deployment when viewing device (#1726)
- Add Priority Queue for deployment groups, allowing devices in a version range earlier updates (#2413)
- Add Releases tab to group release logic (#2424)

### Changed

- Change device field Uptime to Connected For (#2415)
- Don't retry delta generation that will always fail (#2414)
- Replace Scrivener with Flop for pagination (#1656)
- Improve pagers (#1664)
- Make device list refresh in a live but safe way (#2260)
- Use scripts plumbing for connecting code (#2399)
- A bundle of health chart improvements (#2389)
- Make devices index view much faster by deferring filter loading (#2390)
- Make scripts endpoint consistent with api by taking name instead of id (#2398)
- Guard against the 'connection issue' flash not closing upon reconnection (#2383)
- A better Device tab UI experience when there is latency (#2382)
- Remove controller and live view param whitelisting (#2381)
- Deployment Group validations improvements + live socket form recovery (#2380)
- Recoverable forms for Support Scripts and Device settings (#2379)
- Switch all Product nested UIs to the updated design (#2374)
- Improve how device metadata is displayed (#2371)
- Encapsulate logic related to resetting update attempts into a changeset function (#2368)
- Scope by product when getting update stats for deployment (#2366)
- Scope Firmware queries by `product_id` (#2365)
- Make sure calls to fetch Firmware are scoped by Product ID (#2364)
- Use `System.monotonic_time/1` for quick interval calculations (#2363)
- Quokka autosort defstruct and schema (#2324)
- Switch from `phx-change` to `phx-click` (#2349)
- Use "true"/"false" instead of "on"/"off" (Phoenix convention) (#2348)
- Remove the default form "manual update" submit button (#2344)
- Remove unused functions related to checking if a device is online (#2338)
- Encapsulate device communications into a new module, `DeviceLink` (#2331)
- Move device connection pubsub updates to the `Connections` context (#2336)
- Reflect changes from how Link communicates firmware validation (#2335)
- Make sure env is empty when using `System.cmd` (#2333)
- Remove the need to `decode!` all payloads for device heartbeats (#2329)
- A small optimization to `Devices.update_attempted/2` (#2326)
- Update the Phoenix Socket topic mappings (fixes a fastlaning issue) (#2325)
- Smart Device PubSub fastlaning (#2297)
- Quokka single node fixups (#2321)
- Quokka pipe fixups (#2320)
- Quokka config and deprecation fixups (#2319)
- Don't run Oban jobs on device nodes (#2312)
- Quokka block fixups (#2318)
- Run Oban migrations (bump to v13) (#2294)
- Only update the target firmware file with deltas that are smaller (#2308)
- Adding `apt-get upgrade` eliminates hundreds of CVE warnings (#2311)
- Introduce Quokka for automatic lint fixes (defs and line lengths only) (#2293)
- Update the delta file name on upload (#2305)
- Refactor complex macros in NervesHubWeb module (#2298)
- Changes the alarms to list vertically (#2300)
- Remove default subscriptions setup when a device connects (#2296)
- Use jemalloc for our memory allocation (#2265)
- Rework health-check endpoint, spec, and tests (#2292)
- Use `:zip` and `Plug.Upload.random_file/1` where appropriate (#2291)
- Match deployments to devices with nil tags (#2244)
- Improve the logging for duplicate device identifier connection errors (#2285)
- Device filter inflight (#2261)
- Support TLS Version as an Option within SMTP (#2268)
- Improve SSL certificate logging (#2284)
- Relax user role for device event channel (#2279)
- Track firmware delta generation in more detail (#2235)
- Add missing Actor index to Audit Logs table (#2256)
- Add an external device channel for device/firmware updates (#2217)
- Reinstate setting deployment groups on device connect, tests (#2220)
- Remove sentry report on harmless missing source firmware (#2218)
- Increase test coverage for ManagedDeployments, add excoveralls (#2216)
- Reduce the Ecto config we pass to Libcluster (#2215)
- Safer delta updates (#2179)
- Cleanup NervesHub.ManagedDeployments (#2211)
- `spellweaver` wants to know what `bun` to use (#2204)
- Update `libcluster_postgres` and its new simplified config (#2205)
- Stream devices query when creating CSV (#2187)
- Catch invalid version condition errors (#2200)
- Don't send `Unhandled handle_in message` to Sentry (#2201)
- Set a default table engine suited for hosted Clickhouse installs (#2199)
- Add a logout button and some docs (#2197)
- Send 503 status when running script and device is unreachable (#2188)
- Don't close batch-update selects when LiveView updates (#2185)
- Device penalty box revisions (#2158)
- Ensure device priority update tooltip doesn't overlap location map (#2172)
- Reload device after updating extensions (#2173)
- Allow `ScriptController.send/2` to accept a string or integer `timeout` param (#2171)
- Check for delta updates based on deployment group, not product (#2163)
- Allow firmware uploads from products named with spaces (#2157)
- Revise device index pagination (#2148)
- Improve responsiveness for top bar (#2147)
- Remove the progress bar effect when a deployment is paused (#2142)
- Add alias mix check to run various CI checks (#2135)
- Remove need for node and NPM using spellweaver (#2137)
- Set consistent order for products on landing page (#2138)
- Increase DB timeout when mass moving devices in and out of deployment groups (#2130)
- Don't require tags when updating deployment group, changeset refactor (#2107)
- Increase script runner timeout to 30s (#2133)
- Derive certificate URL param from schema (#2115)
- Ignore update on dropdowns in device detail view (#2111)
- Update pre-generated account (#2105)
- Fixes to device logging processing (#2100)
- Use the `OrchestratorRegistration` GenServer for monitoring (#2099)
- Add the `DeviceHealthTruncation` cron back (#2098)
- Handle user presence tracking failing (#2070)
- Monitor deployment processes in worker and report to Sentry (#2085)
- Reinstate script controller API endpoint (#2096)
- Correct our use of  `fill="currentColor"` (#2094)
- Ignore test dir when spell-checking (#2087)
- Add confirming online status with the tracker on device join (#2089)
- Change dev config to match peer verification for prod (#2091)
- Scroll pinned-device tags when there are too many (#2071)
- Use the `citext` column type for a users email (#2077)
- Show a spinner when a Support Script is running (#2079)
- Remove the old OpenAPI spec (#2074)
- Add new templates and LiveViews to build out the product and org UI (#2066)
- Add filtering sidebar component (#2062)
- OrgUser API improvements (#2063)
- A refreshed login experience, with improvements (#2048)
- Don't clean up the async assign on the console tab (#2056)
- OpenAPI spec improvements (#2057)
- Ignore the Dialyzer dir (#2060)
- Show name of user when hovering over initials while viewing device (#2055)
- Add spell check (#2059)
- Use `Phoenix.Param` for cleaner URL generation (#2050)
- Load the device list async, for a better and faster UX (#2038)
- Remove `phoenix_view` elements from the API (#2030)
- Run dialyzer in GH actions, fix dialyzer warnings (#2042)
- Relax null constraint on user_tokens.old_token (#2041)
- Ensure User Token V1 continues to work for now (#2040)
- Remove unneeded :base62 lib  (#2039)
- A revamp of our user token storage and management (#2024)
- UI fixups (#2037)
- Update `esbuild` and the js target it compiles to (#2034)
- Empty state UI tweaks (plus a button fix) (#2033)
- Remove `live_toast` and just use standard flashes (#2029)
- Increase timeouts for device connection updates and deletes (#2032)
- Remove toast cruft (#2031)
- Manual Deployment Recollect (#1970)
- Use hooks instead of LiveComponents (#2026)
- Support device index table row links in webkit (#2025)
- Expand new UI device tests (#2018)
- Default to sorting deployment groups by name while viewing DeploymentGroups.Index (#2022)
- Remove old orchestrator supervisor from application tree (#2020)
- Remove the old orchestrator (#2013)
- Update Phoenix JS dependencies (#2019)
- Improved function naming for toggling automatic updates (#2014)
- Only include specified device in presence stream (#2015)
- Allow the old UI to continue to enable and disable firmware updates when viewing a device (#2010)
- Add proper assigns to DeviceDetailsPage, ensure firmware is loaded on deployment group (#2009)
- Use the max possible jitter when cleaning stale connections (#2003)
- Improve the support script output (#1996)
- Use seconds for the heartbeat interval jitter (#1993)
- Incorporate a random jitter into the device heartbeat (#1992)
- Telemetry for stale connection clean up count (#1991)
- Reduce some of the work the heartbeat needs to do (#1990)
- Filter deployment groups by name (#1978)
- Make sure 'skip queue' firmware update message are sent to devices (#1985)
- Remove padding and box around the console (#1976)
- Cache the `product_id` in the `DeviceConnection` (#1973)
- Reduce font size in console to prevent wrap (#1975)
- Migrate old Deployment audit logs to reference DeploymentGroup (#1969)
- Order Deployments in the various dropdowns (#1966)
- Improve firmware update button on the Device show page (#1965)
- Managed Deployments: Groups and Releases (#1653)
- Backport device_connection indexes, sort when deleting them so index is used (#1964)
- Redirect to newly created deployment (#1963)
- Add the deployment version constraint to the deployments list (#1962)
- Show a toast notification when a console upload starts and finishes (#1950)
- Update Elixir, OTP, Ubuntu, and other CI bits (#1953)
- Address some Dialyzer and Credo warnings (#1941)
- Also check if the product has the health extension enabled (#1940)
- Use the new deployments orchestrator by default (#1922)
- Ensure available deployments match selected devices architecture and platform when batch-updating (#1912)
- Capture support script timeouts (#1923)
- Ignore logging for web requests from the Sentry uptime bot (#1919)
- Run one deployment orchestrator per deployment per cluster (#1865)
- Reinstate deployment version check when device connects (#1918)
- Switch to showing (and sorting) on a devices last connection `established_at` datetime (#1898)
- New UI: Remove the chat from the console (#1900)
- Comment out `recalculation_type` (#1901)
- Cleanly close the device connection during channel tests (#1902)
- Add some missing logic for the "No archive configured" label (#1899)
- Cleanly close sockets in tests (#1895)
- Return a device when calling `Deployments.verify_deployment_membership/1` (#1894)
- `DeviceChannel` should ignore messages but not create Sentry errors (#1892)
- Remove unused heartbeat `handle_info` (#1891)
- Allow for the main DB pool to have a customized pool count (#1888)
- Be intentional with the messages we send to devices (#1880)
- Make sure all health reports are deleted when a device is destroyed (#1878)
- Address a few small credo and dialyzer warnings (#1879)
- Tooltip improvements (#1874)
- Track the link api version in the connection metadata (#1875)
- Remove a remnant of the old `DeviceLink` (#1870)
- Improvements to the 'updating' header on the deployments summary tab (#1868)
- Handle cases where, upon connection, we know the device is already updating (#1869)
- Remove the need to store the devices deployment in the `DeviceChannel` (#1860)
- Enrich the Sentry context with basic user info (#1858)
- Standardize loading a device for the device show page (#1861)
- Add some of the firmware UUID to the select box (#1859)
- Device Cert Auth: Don't fetch data if we don't need it (#1849)
- Dialyzer and credo fixes (#1831)
- Health Report: Only store metadata directly from the device (#1844)
- Broadcast that a device has been updated when setting and clearing deployment (#1846)
- New UI: Allow deletion of scripts (#1845)
- Adjust device_connections worker frequency, increase timeout when deleting in batches (#1839)
- Prefer UNION instead of OR when querying audit_logs when viewing device (#1842)
- Reduce queries made during device socket connection (#1837)
- New UI: Speed up the loading of the device and deployment page tabs (#1833)
- New UI: Enabled and fixed all device bulk actions (#1832)
- Fixes for the New UI org/product list page (#1830)
- New UI: Add support for creating deployments (#1829)
- Remove the need to get a connection before updating it (#1835)
- Remove audit and logger statement from extensions request check (#1828)
- Pass date column to to_string instead of schema (#1827)
- Various fixes found by Dialyzer (#1825)
- Ensure deployments devices are nilified on deletion (#1761)
- Remove old `device_connections` in worker, remove connection state stored on `device` (#1807)
- New UI: Use the consistent buttons on the device show page (#1823)
- Remove a noisy log line (#1822)
- New UI: Consistently style buttons and button links (#1818)
- New UI: Improve the readability of the device list progress bar (#1814)
- Add audit logs when creating or updating script (#1815)
- Add sidebar link for org in org/product menu (#1817)
- New UI: Alignment improvements, and allow entire table cells to be clickable (#1813)
- Handle different metrics cases (cpu temp and usage) (#1810)
- Don't show a link to the archive if there is no archive (#1811)
- New UI: Deployments Time! (#1806)
- Allow unprovisioned devices to set deployments (#1767)
- Move all audit logging to templates (#1709)
- New UI: Product settings (#1802)
- New UI: Support Scripts (#1801)
- New UI some tweaks along the way (#1798)
- New UI: Support Archives (#1797)
- Change use of CPU metrics in health indicator (#1803)
- New UI: Add support for "Add Device" (#1792)
- Correct the file size plug regex (#1790)
- New UI: Firmwares - Part 1 (#1785)
- New UI: Device page - Part 5 - Getting close (#1780)
- New UI: Device page - Part 4 (#1777)
- Rework console.js into LiveView Hook for UI 2.0, organize app.js and existing hooks (#1776)
- New UI : Device page improvements - part 3 (#1772)
- New UI : Device details metrics (#1771)
- New UI working device location (#1770)
- Tiny new UI fixes (#1769)
- Some fully working device pages (#1766)
- New UI Device page - part 1 (#1762)
- Make it clear device has no active alarms (#1765)
- New UI tweaks (#1759)
- Refresh device-related assigns when receiving connection online message, replace `mox` with `mimic` (#1738)
- Allow devices to have empty firmware when checking for deployments (#1749)
- A small device header simplification (#1755)
- Mix task best practises (#1756)
- The `Credo` experiment (#1740)
- Clean stale `DeviceConnection`s (#1747)
- Make orchestrator and resolve_update respect deployment.is_active (#1743)
- Exclude deleted devices from Deployment device counts (#1735)
- `Deployments` context specs (and some improvements) (#1733)
- Relax restrictions when querying for eligible deployments (#1736)
- Create audit logs when setting deployment (#1737)
- Move some Deployment info around (#1732)
- A small `Remove from Deployment` UI tweak (#1729)
- Improve device buttons (#1731)
- Bring back deployment device matching when a device connects (#1720)
- Fetch the signing salt for the web socket connections from the config (#1721)
- Make sure the latest connection is loaded (#1719)
- Rename function for broadcasting extension events (#1717)

### Fixed

- Fix device pager not paging back to page 1 (#1663)
- Only take into account a device's latest connection when processing online and offline counts for products and orgs (#2412)
- Fix device index refresh list callback (#2411)
- Fix expiring inflight updates on device connect (#2410)
- Fix script and device pagination (#2400)
- Fix deployment group tags being merged when editing settings (#2397)
- Fix registration problems where people's names are called invalid (#2377)
- Fix `push-available-update`, and add some tests for the future (#2370)
- Fix a Postgres error when Google profile pic URLs are super long (#2367)
- Fix a SMTP TLS setting that broke the ability to send emails when no TLS version is specified (#2362)
- Correct a function pattern match (#2355)
- Fix the ability to send manual delta updates, and add a test (#2343)
- Fix a bug with product ordering changing when loading `/orgs` (#2339)
- Fix local firmware upload path metadata (#2334)
- Fix the deployment progress progress bar html/css (#2332)
- Fix how manual device location is updated (#2328)
- Fix visual issue with rounded corners on pinned devices table (#2177)
- Fix rendering tags with invalid deployment group params so errors display properly (#2203)
- Fix firmware uploads from API (#2198)
- Fix LiveView warning when uploading device certificates, rehydrate state properly (#2280)
- Fix device status updates while viewing device index (#2178)
- Fix Audit Logs pagination on Device pages (#2257)
- Handle error when creating deltas (#2243)
- Fix deleting and destroying devices in new UI (#2150)
- Fix device certificate management in new UI (#2238)
- Firmware UUIDs are unique to products (#2233)
- Default deployment_group.delta_updates_enabled to false in tests to reflect the default changeset value (#2164)
- Fix filtering devices by tags (#2149)
- Fix metrics time frame not updating when clicking buttons (#2146)
- Fix device details deployment groups layout (#2144)
- Handle improperly formatted API tokens (#2132)
- Fix broken certificate download in new UI (#2109)
- Fix scripts index API endpoint (#2097)
- Fix regression in CLI by reverting API paths for deployments (#2067)
- Fix event name for delete deployment button (#2084)
- Fix firmware install count column when viewing firmwares (#2086)
- Fix flaky managed deployment test (#2088)
- Fix pure text emails (#2073)
- Fix a visual bug where the progress bar was slightly padded (#2065)
- Fix filtering by platform in new UI (#2044)
- Fix incorrect Dialyzer caching (#2049)
- Fixes found after a deploy (#2035)
- Fix moving devices to deployment group while viewing devices index (#2027)
- Fix how device health is updated in the UI (#2000)
- Fix an assigns check in the console component (#2002)
- Fix date comparison when checking certificate status (#2001)
- Fix bug from rebase that was sending extension requests when it shouldn't be (#1967)
- Fix incorrect Firmware UUID shown in firmwares list (#1949)
- Fix console drag-and-drop uploads (#1946)
- Fix a bug with how we were filtering on connection type (#1932)
- Fix starting scripts from API endpoint (#1937)
- Bug fixes from recent PRs (#1928)
- Don't let users with view role update settings or delete devices (#1889)
- Fix an extensions bug related to channels not sharing assigns (#1843)
- Fix: New devices connecting shouldn't cause extension errors (#1834)
- Don't show the metrics last updated time if it is nil (#1826)
- Fix the Dashboard map query and filtering (#1824)
- Stop the `updating` label from messing with the table column (#1821)
- New UI: Fix device counts for deployments (#1812)
- Fix refresh of dynamic templates (#1786)
- New UI: Fix the console resizing logic (#1779)
- New UI: JS hook fixes (#1778)
- Fix a function signature call which recently changed (#1745)
- Fix: Duplicate html tag ids on the Devices list page (#1757)
- Fix a case statement in `NewUI.DeviceLocation` (#1857)
- Make sure firmware is selected when processing `push-update` (#1863)
- Correctly show device updates status (#1952)
- Fix some test imports (#1974)
- Fix issues found by Elixir 1.20 RC (#2428)

### Dependencies

- **bandit**: 1.6.0 -> 1.8.0
- **bcrypt_elixir**: 3.2.0 -> 3.3.2
- **bun**: 1.5.1
- **bunt**: 1.0.0
- **castore**: 1.0.8 -> 1.0.15
- **cc_precompiler**: 0.1.11
- **certifi**: 2.12.0 -> 2.15.0
- **ch**: 0.5.6
- **circular_buffer**: 0.4.1 -> 1.0.0
- **comeonin**: 5.5.0 -> 5.5.1
- **confuse**: 0.2.1
- **crontab**: 1.1.14 -> 1.2.0
- **credo**: 1.7.13
- **dialyxir**: 1.4.3 -> 1.4.7
- **ecto**: 3.12.3 -> 3.13.3
- **ecto_ch**: 0.8.2
- **ecto_psql_extras**: 0.8.1 -> 0.8.8
- **ecto_sql**: 3.12.0 -> 3.13.2
- **elixir_make**: 0.9.0
- **esbuild**: 0.10.0
- **ex_aws**: 2.5.5 -> 2.5.11
- **ex_aws_s3**: 2.5.3 -> 2.5.8
- **excoveralls**: 0.18.5
- **expo**: 0.5.2 -> 1.1.0
- **file_system**: 1.1.1
- **fine**: 0.1.4
- **finch**: 0.20.0
- **floki**: 0.36.2 -> 0.38.0
- **flop**: 0.26.3
- **gettext**: 0.24.0 -> 0.26.2
- **ham**: 0.3.2
- **hammer**: 7.1.0
- **hash_ring**: 0.4.2
- **lazy_html**: 0.1.8
- **libcluster**: 3.5.0
- **libcluster_postgres**: 0.2.0
- **libgraph**: 0.16.0
- **mix_unused**: 0.4.1
- **mjml**: 4.0.0
- **mjml_eex**: 0.12.0
- **nimble_parsec**: 1.4.2
- **nstandard**: 0.1.1
- **number**: 1.0.5
- **oauth2**: 2.1.0
- **oban**: 2.20.1
- **oban_met**: 1.0.3
- **oban_web**: 2.11.4
- **open_api_spex**: 3.22.0
- **open_telemetry_decorator**: 1.5.10
- **opentelemetry**: 1.6.0
- **opentelemetry_api**: 1.4.1
- **opentelemetry_bandit**: 0.3.0
- **opentelemetry_exporter**: 1.9.0
- **opentelemetry_phoenix**: 2.0.1
- **phoenix**: 1.7.14 -> 1.8.1
- **phoenix_ecto**: 4.6.2 -> 4.6.5
- **phoenix_html**: 3.3.4 -> 4.3.0
- **phoenix_live_dashboard**: 0.8.5 -> 0.8.7
- **phoenix_live_reload**: 1.6.1
- **phoenix_live_view**: 0.20.17 -> 1.1.13
- **phoenix_test**: 0.8.1
- **plug**: 1.16.1 -> 1.18.1
- **postgrex**: 0.19.2 -> 0.21.1
- **process_hub**: 0.3.3-alpha
- **quokka**: 2.11.2
- **rustler_precompiled**: 0.7.3
- **sentry**: 10.7.1 -> 11.0.4
- **sizeable**: 1.0.2
- **slipstream**: 1.1.2 -> 1.2.0
- **spellweaver**: 0.1.5
- **swoosh**: 1.17.1 -> 1.19.8
- **tailwind**: 0.4.0
- **telemetry_metrics**: 0.6.2 -> 1.1.0
- **telemetry_metrics_statsd**: 0.7.0 -> 0.7.2
- **tesla**: 1.14.1
- **ueberauth**: 0.10.8
- **ueberauth_google**: 0.12.1
- **unzip**: 0.12.0
- **tzdata**: 1.0.0 -> 1.1.3
- **x509**: 0.8.9 -> 0.9.2

## v2.2.0

Version was used in a tag but not released. Skipped.

## v2.1.0

### Added

- Add the oban integration to Sentry (#1543)
- Add container version tagging (#1549)
- Add device count and estimated device count for Deployment views (#1517)
- Use Chart.js for metrics (#1523)
- Add task for generating randomized device metrics (#1564)
- Add support for a release id for Sentry (#1568)
- Add option for showing updated devices on the map (#1592)
- Clear inflight updates for unhealthy devices (#1620)
- Show helpful message when uploading duplicate firmware (#1627)
- Add support for filtering devices on alarms (#1628)
- Have the calculator use Oban (#1639)
- Save device connection data over time (#1572)
- Add support for OpenTelemetry tracing (#1612)
- Show current alarms on device page (#1648)
- World Map clustering (#1619)

## Changed

- Device channel cleanups (#1546)
- Increase the Repo queue_target (#1545)
- Fix dialyzer warning about use of map where each would do (#1550)
- Use the Endpoint from the socket (#1558)
- Sentry integration tweaks (#1560)
- Remove the NodeReporter metrics logger (#1563)
- Only render connection tooltip when timestamp is present (#1565)
- Logger improvements (foundations) (#1556)
- Allow errors and warnings in test env (#1561)
- Separate logging from metrics (#1571)
- Allow the socket drainer to be configured at runtime (#1577)
- Use the endpoint from the socket (#1579)
- Reintroduce missing custom metrics and metadata to device page (#1578)
- Add y-scale start number as chart parameter (#1580)
- Metrics charts improvements (#1581)
- Only broadcast on terminate/2 if the channel is joined (#1586)
- Display selected option when moving device(s) to other product (#1591)
- Add firmware delta generation back in (#1582)
- Order platform dropdown + add unknown platform as selection (#1599)
- Group by deployment id when counting devices for deployments (#1600)
- Disable console button when device console is not available (#1605)
- Batch insert device metrics (#1613)
- Optimize the queries needed for Accounts.list_org_keys (#1614)
- Increase the Orchestrator timer, and add a jitter (#1615)
- Remove an extra Deployment preload during after_join (#1618)
- Allow publishing docker images from PR (#1626)
- Use PRs HEAD sha for tagging images (#1637)
- Use PR number when looking for publish commit message (#1638)

### Fixed

- Some minor dialyzer fixes (#1553)
- Update mix.exs Elixir version to match .tool-versions (#1621)
- Use the correct endpoint for pubsub broadcasts (#1634)
- Fix an unreachable with/else code path (#1642)
- Use the full module reference for some @specs (#1645)
- Change health section to not show boxes for non-reported default values (#1651)

### Dependencies
- **castore**: 1.0.8 -> 1.0.10
- **ex_aws_s3**: 2.5.3 -> 2.5.5
- **dialyxir**: 1.4.3 -> 1.4.5
- **bcrypt_elixir**: 3.1.0 -> 3.2.0
- **comeonin**: 5.4.0 -> 5.5.0
- **swoosh**: 1.17.1 -> 1.17.3
- **slipstream**: 1.1.1 -> 1.1.2
- **telemetry_metrics_statsd**: 0.7.0 -> 0.7.1
- **ecto**: 3.12.3 -> 3.12.4
- **ecto_sql**: 3.12.0 -> 3.12.1
- **telemetry_metrics**: 0.6.2 -> 1.0.0
- **ecto_psql_extras**: 0.8.1 -> 0.8.2
- **ex_aws**: 2.5.5 -> 2.5.7
- **x509**: 0.8.9 -> 0.8.10
- **postgrex**: 0.19.1 -> 0.19.3
- **floki**: 0.36.2 -> 0.36.3
- **crontab**: 1.1.13 -> 1.1.14
- **sentry**: 10.7.1 -> 10.8.0
- **phoenix_ecto**: 4.6.2 -> 4.6.3
- **gettext**: 0.24.0 -> 0.26.2
- **phoenix_live_dashboard**: 0.8.4 -> 0.8.5
- **bandit**: 1.5.7 -> 1.6.0
- **opentelemetry_bandit**: 0.2.0-rc.1 -> 0.2.0
- **opentelemetry_phoenix**: 2.0.0-rc.1 -> 2.0.0
- **open_telemetry_decorator**: 1.5.7 -> 1.5.8

From `assets/`:
- **webpack**: 5.45.1 -> 5.95.0
- **braces**: 3.0.2 -> 3.0.3

## v2.0.0

Trying to create a Changelog from the previous tagged version `v1.3.0` from
January 2023 is frankly a bit much.

The fundamentals:

- Performant at scale: It is used in production with hundreds of thousands of connected devices. It works well.
- Remove AWS: It is now easy to run and set up on any hosting platform

There is also a lot more. The [initial announcement of 2.0](https://elixirforum.com/t/introducing-nerveshub-2-0/55531/5)
has the basic idea. The only idea that isn't currently actively pursued or
already delivered is MQTT and that is bound to pop up again in the future.

A lot of this work should be credited to Eric Oestrich and he gave an update
on it at [the Nerves Meetup](https://www.youtube.com/watch?v=vSYbSTXL26I).

Jon Carstens covered some of the work during
[his NervesConf talk](https://www.youtube.com/watch?v=lHcC9gwk_rg) as a well.

After the 2.x changes were available Josh Kalderimis joined in and started
looking at ease of use which led to a lot of various improvements but the
biggest one is the alternative device authentication method: Shared Secret

Since then we have contributions from 19 people where Eric Oestrich dominates
the stats. Followed by Josh Kalderimis. Then Jon Carstens.

There are a lot of things planned. SmartRent, NervesCloud and other users of
the project are in active collaboration on improving the feature set, the
performance and the user experience. We want this to be not just a great tool
for developers that choose Nerves but a surprising delight and joy to use.

### Migration

You should be able to migrate using the Ecto migrations. Nothing should be
break if you migrate a 1.x install to the 2.x releases. We still recommend
that you set aside time for dealing with anything unusual that might come up.

You may also need some time to deprovision the AWS resources you no longer
need.
