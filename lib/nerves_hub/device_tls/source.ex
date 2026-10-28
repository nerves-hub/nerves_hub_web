defmodule NervesHub.DeviceTLS.Source do
  @moduledoc """
  Where `NervesHub.DeviceTLS.Reloader` gets the device endpoint's
  keypair from.

  A source only fetches. Checking what it returns and installing it is the
  reloader's job, so a source cannot put an unchecked keypair in front of
  devices however it misbehaves.
  """

  @type state :: term()

  @type material :: %{key_pem: String.t(), chain_pem: String.t()}

  @doc "Sets up the source from its options. Must not reach the network."
  @callback init(keyword()) :: {:ok, state()}

  @doc """
  Returns the keypair to serve, if it differs from the one whose leaf has
  `installed_sha1` -- `nil` when nothing is installed yet.
  """
  @callback fetch(installed_sha1 :: String.t() | nil, state()) ::
              {:ok, material(), state()} | {:unchanged, state()} | {:error, String.t(), state()}

  @doc """
  Hears how the last fetch went: installed, or turned away and why. For a
  source that reports back to wherever it fetched from.
  """
  @callback installed(:ok | {:error, String.t()}, state()) :: state()

  @doc """
  Whether a message the reloader received means there is something new to
  fetch. For a source that can be told, rather than only asked.
  """
  @callback changed?(message :: term()) :: boolean()

  @optional_callbacks changed?: 1
end
