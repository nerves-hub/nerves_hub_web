# Slack

An organization can connect Slack workspaces on its **Integrations** page and post its device notifications to their channels. Connecting a workspace installs this instance's Slack app there, through Slack's own install screen.

The integration is only shown when the instance has a Slack app configured. NervesCloud has one. A self-hosted instance needs its own, set up as below.

## Connecting a workspace

An organization admin clicks **Add to Slack** and approves the install in Slack. Slack sends them back to the Integrations page, where the workspace is listed with who connected it.

- A workspace can be connected to more than one organization. Each connection is separate, and disconnecting one leaves the others.
- Installing again in a connected workspace refreshes its token and scopes, without connecting it twice.
- Organization-wide installs on Slack Enterprise Grid are refused. Install the app in a single workspace instead.

**Disconnect** removes the connection. When it was the last organization connected to that workspace, NervesHub also revokes the app's token, which removes the app from the workspace. If someone removes the app from inside Slack, NervesHub hears about it and disconnects every organization connected to that workspace. Each of these is recorded in the organization's audit log.

## Channel notifications

Under a connected workspace, **Add channel** picks a channel, the products whose events it gets (every product, including ones added later, or a chosen few), and the events. It takes the organization `manage` role, as webhooks do. The channel list is the one Slack gives the app: every public channel, and the private channels the app has been invited to. To post to a private channel, invite the NervesHub app to it first.

| Event | Posted when |
| --- | --- |
| Health status changed | A device's health status moves, such as from healthy to warning. |
| Update failed | A device's update fails, stops reporting progress, or ends with the device back on its old firmware. |
| Update succeeded | A device finishes updating. |
| New error | A device reports an error not seen before in its product. |
| Error reopened | An error that was marked resolved happens again. A muted error does not reopen. |
| Product notifications | NervesHub adds something to a product's Notifications page, such as a halted deployment workflow or a webhook it turned off. A notification that recurs is posted only the first time. |

Events are held for 15 seconds before they are posted, and everything held for a channel goes out as one message per kind of event. A single event gets a message of its own. A burst, such as a fleet's health changing at once, gets one message with a count and the first ten devices, so the channel is not buried. Device names link to the device in NervesHub. Anything a device sent, such as a failure reason, is escaped, so it cannot mention `@channel` or become a link.

**Send test message** posts a message to the channel straight away, saying what it will get.

### When posting fails

- If the channel is archived or deleted, or the app was removed from it, NervesHub turns the channel off. Each product it was getting events for gets a notification saying why. Fix the cause, then turn the channel back on from the Integrations page.
- If Slack asks NervesHub to slow down, it waits as long as Slack says.
- Any other failure is retried after 10 seconds, a minute and five minutes. What still could not be posted is tried again with the channel's next event.
- Events held for more than an hour are dropped rather than posted late.

## What NervesHub keeps

For each workspace, NervesHub keeps its id and name, the app's bot user, the scopes granted, and the bot token Slack issued. The bot token is encrypted with AES-256-GCM before it is stored, using `SECRETS_ENCRYPTION_KEY`, so a copy of the database alone does not reveal it.

The app asks for these bot scopes when it is installed:

| Scope | Why |
| --- | --- |
| `chat:write` | Post device notifications to channels. |
| `chat:write.public` | Post to public channels without being invited first. |
| `channels:read` | List public channels to choose from. |
| `groups:read` | List private channels the app has been invited to. |
| `commands` | Slash commands and message actions. |

Slack only grants new scopes when the app is installed again, so the app asks for all of them now. That way a workspace connected today does not need reconnecting when commands arrive.

## Setting up a Slack app for your instance

1. Go to <https://api.slack.com/apps>, choose **Create New App**, then **From a manifest**, and pick a workspace to develop it in.
2. Paste the manifest below, with `https://nerves-hub.example.com` replaced by your instance's URL.
3. Under **Manage Distribution**, turn on public distribution so that workspaces other than the development one can install the app.
4. From **Basic Information**, set `SLACK_CLIENT_ID`, `SLACK_CLIENT_SECRET` and `SLACK_SIGNING_SECRET` on the instance, plus a `SECRETS_ENCRYPTION_KEY` (`openssl rand -base64 32`). See [runtime configuration](runtime_configuration.md#slack).
5. Restart the instance. **Add to Slack** appears on each organization's Integrations page.

```json
{
  "display_information": {
    "name": "NervesHub",
    "description": "Device notifications from NervesHub"
  },
  "features": {
    "bot_user": {
      "display_name": "NervesHub",
      "always_online": true
    }
  },
  "oauth_config": {
    "redirect_urls": ["https://nerves-hub.example.com/integrations/slack/oauth/callback"],
    "scopes": {
      "bot": ["chat:write", "chat:write.public", "channels:read", "groups:read", "commands"]
    }
  },
  "settings": {
    "event_subscriptions": {
      "request_url": "https://nerves-hub.example.com/integrations/slack/events",
      "bot_events": ["app_uninstalled", "tokens_revoked"]
    },
    "org_deploy_enabled": false,
    "socket_mode_enabled": false,
    "token_rotation_enabled": false
  }
}
```

Slack checks the events URL when the manifest is saved, so the instance must already be reachable at that URL with `SLACK_SIGNING_SECRET` set. If it is not yet, save the manifest without `event_subscriptions`, configure and restart the instance, then add them back.

## Requests from Slack

Slack calls the instance under `/integrations/slack/`. Every request there must carry a valid `X-Slack-Signature` for the app's signing secret, and be no more than five minutes old. Anything else is refused with a 401. When the instance has no Slack app configured, these URLs answer 404.
