import '../css/app.scss'

import 'phoenix_html'
import 'bootstrap'
import '@popperjs/core'
import $ from 'jquery'
import { Socket } from 'phoenix'
import { LiveSocket } from 'phoenix_live_view'
import Josh from 'joshjs'

let dates = require('./dates')
let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute('content')

try {
  new Josh()
} catch (error) {
  console.warn('Failed to initialize Josh: ', error)
}

$(function () {
  $('.custom-upload-input').on('change', function () {
    let fileName = $(this).val().split('\\').pop()
    $(this)
      .siblings('.custom-upload-label')
      .removeClass('not-selected')
      .addClass('selected')
      .html("Selected File: <div class='file-name'>" + fileName + '</div>')
  })
})

document.querySelectorAll('.date-time').forEach((d) => {
  d.innerHTML = dates.formatDateTime(d.innerHTML)
})

function bufferEncode(value) {
  let binary = ''
  const bytes = new Uint8Array(value)
  bytes.forEach((b) => (binary += String.fromCharCode(b)))
  return window.btoa(binary)
}

function bufferDecode(value) {
  return Uint8Array.from(atob(value), (c) => c.charCodeAt(0))
}

let Hooks = {}

Hooks.FidoCreate = {
  mounted() {
    this.handleEvent(
      'create-fido-credential',
      ({ challenge, rp, user, attestation, pubKeyCredParams }) => {
        navigator.credentials
          .create({
            publicKey: {
              challenge: bufferDecode(challenge),
              rp,
              user: {
                id: bufferDecode(user.id),
                name: user.name,
                displayName: user.displayName,
              },
              attestation,
              pubKeyCredParams,
            },
          })
          .then(
            function (newCredential) {
              this.pushEvent('fido-credential-created', {
                rawId: bufferEncode(newCredential.rawId),
                type: newCredential.type,
                clientDataJSON: bufferEncode(
                  newCredential.response.clientDataJSON
                ),
                attestationObject: bufferEncode(
                  newCredential.response.attestationObject
                ),
              })
            }.bind(this)
          )
      }
    )
  },
}

Hooks.FidoGet = {
  mounted() {
    this.handleEvent(
      'get-fido-credential',
      ({ challenge, allowCredentials, rpId }) => {
        navigator.credentials
          .get({
            publicKey: {
              challenge: bufferDecode(challenge),
              allowCredentials: allowCredentials.map(({ id, type }) => ({
                id: bufferDecode(id),
                type,
              })),
              userVerification: 'preferred',
              rpId,
            },
          })
          .then(
            function handleCredential(credential) {
              this.pushEvent('fido-credential-received', {
                id: credential.id,
                rawId: bufferEncode(credential.rawId),
                type: credential.type,
                response: {
                  authenticatorData: bufferEncode(
                    credential.response.authenticatorData
                  ),
                  clientDataJSON: bufferEncode(
                    credential.response.clientDataJSON
                  ),
                  signature: bufferEncode(credential.response.signature),
                  userHandle: bufferEncode(credential.response.userHandle),
                },
              })
            }.bind(this)
          )
          .catch(
            function handleError(e) {
              this.pushEvent('fido-authentication-failed', e)
            }.bind(this)
          )
      }
    )
  },
}

let liveSocket = new LiveSocket('/live', Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
})

liveSocket.connect()
