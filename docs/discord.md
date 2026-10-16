# Discord

An organization can post its device notifications to Discord channels from its **Integrations** page. Each channel gets them through a webhook made in that channel. Nothing needs setting up on the instance, and NervesHub only ever calls out to Discord, so it works from an instance behind a VPN too.

## Adding a channel

1. In Discord, open the channel's settings (**Edit Channel**) and choose **Integrations**, then **Webhooks**. Making a webhook takes the **Manage Webhooks** permission in that channel.
2. Choose **New Webhook**, then **Copy Webhook URL**.
3. On the organization's Integrations page, under Discord, choose **Add channel**. Give it a name to know it by, paste the URL, and choose the products and events it gets.

Adding, changing and removing a channel takes the organization `manage` role, as webhooks, Slack channels and Teams channels do. Everyone in the organization sees each channel's name, events, products and state.

Discord does not tell NervesHub a channel's name, so the name is whatever the person adding it typed. The URL is all it takes to post to the channel, so NervesHub stores it encrypted with `SECRETS_ENCRYPTION_KEY` and never shows it again. Editing a channel leaves its URL as it was unless a new one is pasted in. Only Discord's own webhook URLs (`https://discord.com/api/webhooks/…`, or the `discordapp.com`, `canary` and `ptb` hosts) are accepted.

## What is posted

A Discord channel can get the same events as a Slack or Teams channel: health status changes, failed and successful updates, new and reopened errors, deployment workflow steps, and product notifications. See [Slack](slack.md#channel-notifications) for what each one means.

Events are held for 15 seconds, then posted as one message per kind of event, in the order each kind first happened. A single event gets an embed of its own, titled with what happened and linked to its page in NervesHub; a burst gets a count and the first ten devices, each linked. Messages are posted under the instance's name (`FRIENDLY_PLATFORM_NAME`).

Anything a device sent is escaped, so Discord's markdown in it is shown rather than followed, and every message is posted with mentions turned off, so nothing in it can ping `@everyone` or anybody else.

A channel webhook only posts: there are no buttons that act, as there are in Slack. A workflow waiting for approval is approved on the deployment group's page, which its message links to.

**Send test message** posts a message to the channel straight away, saying what it will get.

## When posting fails

- If Discord refuses the webhook (it was deleted, or its URL no longer works), NervesHub turns the channel off. Each product it was getting events for gets a notification saying why. Make a new webhook and paste its URL into the channel, which turns it back on.
- If Discord asks NervesHub to slow down, it waits as long as Discord says.
- Any other failure is retried after 10 seconds, a minute and five minutes. What still could not be posted is tried again a minute or so later, the same way.
- Events held for more than an hour are dropped rather than posted late.
