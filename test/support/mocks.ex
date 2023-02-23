Code.compiler_options(ignore_module_conflict: true)

Mox.defmock(NervesHub.DeltaUpdaterMock, for: NervesHub.Firmwares.DeltaUpdater)
Mox.defmock(NervesHub.UploadMock, for: NervesHub.Firmwares.Upload)
