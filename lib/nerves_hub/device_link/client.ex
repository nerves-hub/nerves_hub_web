defmodule NervesHub.DeviceLink.Client do
  @moduledoc """
  What a process holding a device's connection calls.

  Every function here goes through `NervesHub.DeviceLink.Dispatcher`, so where
  the work runs is a configuration decision rather than something baked into
  each call site. This is the complete list of what a connection ever needs from
  the platform — if something is missing from it, a connection cannot ask for it.

  Callers that are not holding a device connection should use
  `NervesHub.DeviceLink` directly; there is nothing to dispatch for them.
  """

  alias NervesHub.DeviceLink.Authentication
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.DeviceLink.Dispatcher
  alias NervesHub.DeviceLink.Effect
  alias NervesHub.DeviceLink.PeerVerification
  alias NervesHub.DeviceLink.Session
  alias NervesHub.Extensions.Dispatch, as: ExtensionDispatch

  # ---------------------------------------------------------------- connection

  @spec verify_peer(der :: binary(), event :: PeerVerification.event()) ::
          :valid | {:fail, PeerVerification.reason()}
  def verify_peer(der, event), do: Dispatcher.call(:verify_peer, [der, event])

  @spec authenticate(Authentication.credentials()) :: {:ok, DeviceInfo.t()} | {:error, :invalid_auth}
  def authenticate(credentials), do: Dispatcher.call(:authenticate, [credentials])

  @spec connect(DeviceInfo.t()) :: {:ok, DeviceInfo.t()} | {:error, Ecto.Changeset.t()}
  def connect(device_info), do: Dispatcher.call(:connect, [device_info])

  @spec heartbeat(connection_ref :: String.t()) :: :ok | :error
  def heartbeat(connection_ref), do: Dispatcher.call(:heartbeat, [connection_ref])

  @spec disconnect(connection_ref :: String.t(), reason :: String.t() | nil) :: :ok | {:error, any()}
  def disconnect(connection_ref, reason \\ nil), do: Dispatcher.call(:disconnect, [connection_ref, reason])

  # ------------------------------------------------------------------- device

  @spec device_join(DeviceInfo.t(), params :: map()) :: {:ok, Session.t(), [Effect.t()]} | {:error, any()}
  def device_join(device_info, params), do: Dispatcher.call(:device_join, [device_info, params])

  @spec device_message(Session.t(), event :: String.t(), payload :: map()) :: {Session.t(), [Effect.t()]}
  def device_message(session, event, payload), do: Dispatcher.call(:device_message, [session, event, payload])

  @spec device_notify(Session.t(), message :: term()) :: {Session.t(), [Effect.t()]}
  def device_notify(session, message), do: Dispatcher.call(:device_notify, [session, message])

  @spec device_broadcast(Session.t(), event :: String.t(), payload :: map()) :: {Session.t(), [Effect.t()]}
  def device_broadcast(session, event, payload), do: Dispatcher.call(:device_broadcast, [session, event, payload])

  # --------------------------------------------------------------- extensions

  @spec extensions_join(DeviceInfo.t(), extension_versions :: map()) ::
          {[String.t()], ExtensionDispatch.extensions()}
  def extensions_join(device_info, versions), do: Dispatcher.call(:extensions_join, [device_info, versions])

  @spec extension_message(ExtensionDispatch.extensions(), scoped_event :: String.t(), payload :: term()) ::
          {:ok, ExtensionDispatch.extensions(), [Effect.t()]} | :unknown
  def extension_message(extensions, scoped_event, payload),
    do: Dispatcher.call(:extension_message, [extensions, scoped_event, payload])

  @spec extension_info(ExtensionDispatch.extensions(), module(), msg :: term()) ::
          {:ok, ExtensionDispatch.extensions(), [Effect.t()]}
  def extension_info(extensions, module, msg), do: Dispatcher.call(:extension_info, [extensions, module, msg])
end
