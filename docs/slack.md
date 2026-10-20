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
| Workflow step started | A deployment group's workflow begins a step, or begins it again after somebody retries it. |
| Workflow waiting for approval | A workflow reaches a step that holds the rollout until somebody approves it. |
| Workflow step completed | Every device a step covers is on the release's firmware, or somebody approved an approval step. |
| Workflow step failed | Too many of a step's devices fail to update, and the rollout stops there. |
| Workflow step skipped | Somebody skips a step. |
| Product notifications | NervesHub adds something to a product's Notifications page, such as a halted deployment workflow or a webhook it turned off. A notification that recurs is posted only the first time. A channel that also gets "Workflow waiting for approval" or "Workflow step failed" hears about a halted workflow from both. |

Events are held for 15 seconds before they are posted, and everything held for a channel goes out as one message per kind of event, in the order each kind first happened. A single event gets a message of its own. A burst, such as a fleet's health changing at once, gets one message with a count and the first ten devices, so the channel is not buried. Device names link to the device in NervesHub. Anything a device sent, such as a failure reason, is escaped, so it cannot mention `@channel` or become a link.

**Send test message** posts a message to the channel straight away, saying what it will get.

### When posting fails

- If the channel is archived or deleted, or the app was removed from it, NervesHub turns the channel off. Each product it was getting events for gets a notification saying why. Fix the cause, then turn the channel back on from the Integrations page.
- If Slack asks NervesHub to slow down, it waits as long as Slack says.
- Any other failure is retried after 10 seconds, a minute and five minutes. What still could not be posted is tried again a minute or so later, the same way.
- Events held for more than an hour are dropped rather than posted late.

## Acting on devices from Slack

A message about a single device has three buttons: **Open in NervesHub**, **Identify** and **Reboot**, which asks for confirmation first. Messages that summarize many devices have none.

Identify and Reboot are done as a NervesHub user, so each person links their Slack account to their NervesHub account first. The first time someone clicks one of these buttons, Slack shows them, and only them, a link to a NervesHub page. There they sign in to NervesHub if they need to, then sign in with Slack. The Slack account linked is the one Slack says they signed in as, so nobody can link somebody else's Slack account, or get someone else to link theirs. Nothing is matched by email, because the workspace decides what email a Slack user has. A link is made once and lasts until it is removed. Links are listed under **Account Settings**, with when each was last used, so one nobody recognises stands out, and can be removed there.

When a linked user clicks, NervesHub checks, at that moment:

- the device's organization is connected to the workspace the click came from,
- the linked NervesHub user is a member of that organization, and their role there can reboot or identify devices, as it would in NervesHub,
- the device is online.

If any check fails, only the person who clicked is told why. If they all pass, the device is asked to reboot or identify itself, the audit log records the user with "from Slack", and a reply in the message's thread tells the channel who did what.

A device asked to reboot from Slack is not asked again from Slack for a minute, so a double click, two people clicking at once, or a button and a command together reboot it once. Whoever is refused is told who rebooted it. Each request Slack sends is acted on once, so one replayed while its signature is still good does nothing.

## Acting on deployment workflows from Slack

A workflow waiting for approval has an **Approve** button, and a workflow step that failed has **Retry** and **Skip**. Each asks for confirmation, then does what the same button on the deployment group's page does, as the linked NervesHub user. Both kinds of message also have **Open in NervesHub**, which opens the deployment group.

The checks are the device buttons' (above): the deployment group's organization is connected to the workspace, and the linked user's role there can change deployment groups, which takes `manage`. A message can be clicked long after it was posted, so NervesHub also checks that the step still belongs to the deployment group's current release and is still waiting for approval, or still failed. If it was approved or skipped since, the person who clicked is told by whom.

A step is acted on from Slack at most once every 30 seconds, so a double click, or two people clicking at once, approve or retry it once. What was done is recorded in the deployment group's audit log with "from Slack".

Once a step is approved, retried or skipped, from Slack, the deployment group's page or the API, every message with buttons for it is edited: the step's buttons give way to who did what, such as "Approved by Alice". The other steps on a message keep theirs. When a deployment group gets a new release, the messages for its previous release's steps say that release was replaced, since those steps can no longer be acted on. A message is kept up to date for 30 days; after that, its buttons stay, and clicking one still checks the step first. Messages posted before NervesHub kept them up to date are not edited; clicking one of those still posts who did what in its thread.

## Slash commands

`/nerveshub` works in any channel of a connected workspace, as the NervesHub user the Slack user linked, with the same checks as the buttons:

| Command | Does |
| --- | --- |
| `/nerveshub device <identifier>` | Shows the device's connection, firmware version, health and product, with its buttons and **Share in channel**, which posts the card to the channel, saying who shared it. |
| `/nerveshub identify <identifier>` | Asks the device to identify itself. |
| `/nerveshub reboot <identifier>` | Reboots the device. |
| `/nerveshub script <identifier>` | Lists the support scripts for the device's product. |
| `/nerveshub script <identifier> <name>` | Runs a support script on the device, and shows its output. |
| `/nerveshub link` | Links your Slack account to your NervesHub account. |
| `/nerveshub help` | Lists these. |

What a command shows is seen only by whoever typed it. That includes a script's output, which can hold anything the device does, and is cut at 2,900 characters. The output comes with a **Share in channel** button: whoever ran the script can post it to the channel, as themselves, once, within 30 minutes. A reboot or identify that was done is posted to the channel, saying who did it, and recorded in the device's audit log as the buttons' are. A script run from Slack is recorded in the audit log too.

Viewing a device and running support scripts take the organization's `view` role, as they do in NervesHub. Identify and reboot take `manage`.

## Link previews

A link to a device's page, or a deployment group's, posted in a connected workspace is previewed under the message. A device gets the card `/nerveshub device` shows, without its buttons. A deployment group gets whether it is active, its current release and firmware, where its workflow is, and how many devices it has. Any of a page's tabs counts, and at most five links in a message are previewed. Slack also asks for a preview while a link is still being typed, and NervesHub gives the same one.

Everyone in the conversation sees a preview, but Slack only says who posted the link, so the preview is checked against them, as **Share in channel** is: posting a link is sharing what it shows. Their linked NervesHub account must be a member of the organization the link points into, that organization must be connected to the workspace, and their role must let them see the page. A link they may not see gets no preview, and nobody is told why. Someone who has not linked their account is asked to, in a message only they see, and the link gets no preview until they do.

Only links to this instance are previewed, and only once its domain is one of the Slack app's unfurl domains (see the manifest below). A workspace connected before link previews arrived has to install the app again for them, since Slack only grants the new scopes on install. The Integrations page says so under the workspace: an admin clicks **Add to Slack** and chooses the same workspace, which refreshes its token and scopes without connecting it twice.

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
| `links:read` | Hear about links to this instance posted in Slack. |
| `links:write` | Preview them. |

Slack only grants new scopes when the app is installed again. The app asked for everything up to `commands` from the start; the `links` scopes arrived with link previews, so a workspace connected before then installs the app again to get them.

Script output run from Slack is kept for 30 minutes, so that whoever ran it can share it, and is then deleted.

For each message with buttons for workflow steps, NervesHub keeps its channel and timestamp, the events it was built from, and what was done to each step, so that it can edit the message. That is deleted once every step on it was dealt with, Slack says the message is gone, or 30 days have passed.

For each linked Slack user, NervesHub keeps their Slack user id and name, the workspace's id and name, and the NervesHub user they linked to. Signing in with Slack asks for the `openid` and `profile` scopes, only to read who signed in; NervesHub does not keep the token.

## Setting up a Slack app for your instance

1. Go to <https://api.slack.com/apps>, choose **Create New App**, then **From a manifest**, and pick a workspace to develop it in.
2. Paste the manifest below, with `https://nerves-hub.example.com` replaced by your instance's URL.
3. Under **Manage Distribution**, turn on public distribution so that workspaces other than the development one can install the app.
4. From **Basic Information**, set `SLACK_CLIENT_ID`, `SLACK_CLIENT_SECRET` and `SLACK_SIGNING_SECRET` on the instance, plus a `SECRETS_ENCRYPTION_KEY` (`openssl rand -base64 32`). See [runtime configuration](runtime_configuration.md#slack).
5. Optionally, set `FRIENDLY_PLATFORM_NAME` to the name your users know the instance by. Slack messages and the Slack pages use it ("Open in NervesHub" by default).
6. Restart the instance. **Add to Slack** appears on each organization's Integrations page.

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
    },
    "slash_commands": [
      {
        "command": "/nerveshub",
        "url": "https://nerves-hub.example.com/integrations/slack/commands",
        "description": "Check on and act on NervesHub devices",
        "usage_hint": "device | identify | reboot | script <identifier> [script] | link | help",
        "should_escape": false
      }
    ],
    "unfurl_domains": ["nerves-hub.example.com"]
  },
  "oauth_config": {
    "redirect_urls": [
      "https://nerves-hub.example.com/integrations/slack/oauth/callback",
      "https://nerves-hub.example.com/integrations/slack/link/callback"
    ],
    "scopes": {
      "bot": ["chat:write", "chat:write.public", "channels:read", "groups:read", "commands", "links:read", "links:write"]
    }
  },
  "settings": {
    "event_subscriptions": {
      "request_url": "https://nerves-hub.example.com/integrations/slack/events",
      "bot_events": ["app_uninstalled", "tokens_revoked", "link_shared"]
    },
    "interactivity": {
      "is_enabled": true,
      "request_url": "https://nerves-hub.example.com/integrations/slack/interactivity"
    },
    "org_deploy_enabled": false,
    "socket_mode_enabled": false,
    "token_rotation_enabled": false
  }
}
```

Slack checks the events URL when the manifest is saved, so the instance must already be reachable at that URL with `SLACK_SIGNING_SECRET` set. An instance Slack cannot reach uses Socket Mode instead (below). If it is not yet, save the manifest without `event_subscriptions`, configure and restart the instance, then add them back.

An app created before buttons arrived needs `interactivity` added to its manifest, and the `/integrations/slack/link/callback` redirect URL. Without them, clicking Identify or Reboot shows an error, and linking an account fails. An app created before slash commands arrived needs `slash_commands` added. One created before link previews needs `unfurl_domains`, the `links:read` and `links:write` scopes, and the `link_shared` event.

Register the instance's own host as its unfurl domain. Subdomains of a registered domain are matched too, so registering a parent domain shared by several instances would send each instance's app the others' links. Slack sends a link to only one app per workspace, the one installed there first, when two register the same domain.

## An instance Slack cannot reach (Socket Mode)

Slack sends events, button clicks and slash commands to the instance's URLs. An instance behind a VPN, or a firewall Slack cannot get through, never receives them. Posting notifications and editing messages still work there, since the instance calls Slack, and so do installing the app and linking accounts, since those go through the person's browser, which is on the VPN. Buttons, `/nerveshub` and link previews do not.

Socket Mode turns that around: the instance opens connections to Slack, and Slack sends everything down them. To use it:

1. Create the app from the manifest below instead: Socket Mode on, and no request URLs. The redirect URLs stay, because only browsers follow them.
2. Under **Basic Information**, generate an **App-Level Token** with the `connections:write` scope, and set it as `SLACK_APP_TOKEN` alongside `SLACK_CLIENT_ID`, `SLACK_CLIENT_SECRET` and `SECRETS_ENCRYPTION_KEY`. `SLACK_SIGNING_SECRET` is not needed; without it, the instance's `/integrations/slack/` URLs answer 404.
3. Let the instance reach `slack.com` and the WebSocket hosts Slack hands out, such as `wss-primary.slack.com`, over HTTPS.

Each web node keeps two connections open, so one carries on while Slack replaces the other, which it does every few hours. Slack allows ten connections per app, so an instance can have up to five web nodes in Socket Mode. Slack does not list Socket Mode apps in its Marketplace, which a self-hosted instance's app would not be in anyway.

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
    },
    "slash_commands": [
      {
        "command": "/nerveshub",
        "description": "Check on and act on NervesHub devices",
        "usage_hint": "device | identify | reboot | script <identifier> [script] | link | help",
        "should_escape": false
      }
    ],
    "unfurl_domains": ["nerves-hub.example.com"]
  },
  "oauth_config": {
    "redirect_urls": [
      "https://nerves-hub.example.com/integrations/slack/oauth/callback",
      "https://nerves-hub.example.com/integrations/slack/link/callback"
    ],
    "scopes": {
      "bot": ["chat:write", "chat:write.public", "channels:read", "groups:read", "commands", "links:read", "links:write"]
    }
  },
  "settings": {
    "event_subscriptions": {
      "bot_events": ["app_uninstalled", "tokens_revoked", "link_shared"]
    },
    "interactivity": {
      "is_enabled": true
    },
    "org_deploy_enabled": false,
    "socket_mode_enabled": true,
    "token_rotation_enabled": false
  }
}
```

## Requests from Slack

Slack calls the instance under `/integrations/slack/`. Every request there must carry a valid `X-Slack-Signature` for the app's signing secret, and be no more than five minutes old. Anything else is refused with a 401. When the instance has no Slack app configured, or no signing secret because it uses Socket Mode alone, these URLs answer 404.
