# Auth Requests

An auth request is one API request, authenticated by a person approving it in
their browser instead of by a token. It is for clients that have no token yet,
or shouldn't keep one: the CLI logging in, or a device asking for its own
credentials while it is being provisioned.

The client describes the request it wants to make and holds a stream open. The
person types the code the client shows into NervesHub, sees what is being
asked, and approves or denies it. On approval the request runs as that person,
through the same routes, permission checks and audit logs as any other API
request, and the client receives the route's response on the stream.

Approval only establishes who the request runs as. It grants nothing the
person couldn't already do, so a route that the person isn't allowed to use
answers with its usual refusal, and that is what the client receives.

## Making a request

```
POST /api/auth_requests
Content-Type: application/json
Accept: text/event-stream

{
  "method": "POST",
  "path": "/api/users/me/tokens",
  "body": {"note": "nerves_hub_cli on jane-laptop"},
  "note": "nerves_hub_cli 3.2.0"
}
```

- `method` is one of `GET`, `POST`, `PUT`, `PATCH` or `DELETE`.
- `path` is an API path starting with `/api/`, with any query string. It can't
  be `/api/auth_requests` itself.
- `body`, optional, is a JSON object, sent to the route as JSON. At most 64KB.
- `note`, optional, is shown to the person approving, labelled as provided by
  the requester. At most 255 characters.

An invalid request is answered with `422` and `{"errors": {"detail": "..."}}`
as usual. Otherwise the response is `200` with `Content-Type:
text/event-stream`, and stays open.

The endpoint is rate limited per address, like the rest of the unauthenticated
API.

## The stream

[Server-sent events](https://html.spec.whatwg.org/multipage/server-sent-events.html),
each an `event:` line and a JSON `data:` line:

```
event: pending
data: {"code":"WDJB-MJHT","verification_uri":"https://manage.nervescloud.com/auth/approve","expires_in":600}

: keepalive

event: approved
data: {"user":{"name":"Jane","email":"jane@iot-company.com"}}

event: response
data: {"status":200,"content_type":"application/json; charset=utf-8","body":{"data":{"name":"Jane","email":"jane@iot-company.com","token":"nhu_..."}}}
```

| Event | Data | Then |
| --- | --- | --- |
| `pending` | `code`, `verification_uri`, `expires_in` (seconds) | Show the code and URL to the person. |
| `approved` | `user`: the `name` and `email` the request runs as | The request is running. |
| `response` | `status`, `content_type`, and `body` (decoded when JSON) of the route's response | The stream ends. |
| `denied` | `{}` | The stream ends. The request was not run. |
| `expired` | `{}` | The stream ends. The request was not run. |

Lines starting with `:` are comments, sent every 15 seconds while nothing else
is, so that proxies don't close an idle stream. Ignore them.

If the stream drops before it ends, the request is gone: nothing about it is
stored, and its code stops working once the server notices, at the next
keepalive or the one after. Start a new one.

## Showing the code

Show both the URL and the code, and ask the person to type the code. Don't put
the code in a URL or open a URL containing it: having to type it is what stops
a link alone from getting someone's request approved by somebody else. Opening
the plain `verification_uri` in a browser is fine.

Once the stream reports `approved`, show who the request is running as. A code
can be approved by anyone signed in who sees it, and the request then runs as
them; showing the name lets the person notice.

## Logging in

The CLI logs in by making an auth request for `POST /api/users/me/tokens`,
which creates an API token for whoever approves it and returns it in the
response. The token is then stored and used as any other.

## How it works

`NervesHubWeb.AuthRequests` holds the details. In short, the process serving
the stream is the pending request: it registers under its code in the `"web"`
Group cluster, with the request in the registration's metadata, so the approval
page on any web node can find and show it. A decision is a message to that
process. It unregisters before acting on one, so a request is decided at most
once, then dispatches the request through the endpoint with the approving user
in `conn.private`, which `NervesHubWeb.API.Plugs.FetchCurrentUser` honours in
place of a token.

Each request is logged and emits `[:nerves_hub, :auth_request, event]`
telemetry for `start`, `approved`, `completed`, `denied`, `expired` and
`closed`, with the method, path, client address and user agent, and the user
once one is known.
