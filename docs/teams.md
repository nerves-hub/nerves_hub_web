# Microsoft Teams

An organization can post its device notifications to Microsoft Teams channels from its **Integrations** page. Each channel gets them through a Workflows webhook made in that channel. Nothing needs setting up on the instance.

Workflows webhooks replaced Teams' incoming webhooks (Office 365 connectors), which Microsoft retired in May 2026. A connector URL (on `webhook.office.com`) is refused, with a message saying to make a Workflows webhook instead.

## Adding a channel

1. In Teams, open the channel's **More options** menu and choose **Workflows**.
2. Pick the **Send webhook alerts to a channel** template, check the team and channel, and add the workflow.
3. Copy the URL Teams shows.
4. On the organization's Integrations page, under Microsoft Teams, choose **Add channel**. Give it a name to know it by, paste the URL, and choose the products and events it gets.

Adding, changing and removing a channel takes the organization `manage` role, as webhooks and Slack channels do. Everyone in the organization sees each channel's name, events, products and state, and the host its webhook is on.

Teams does not tell NervesHub a channel's name, so the name is whatever the person adding it typed. The URL is the only thing that lets anyone post to the channel, so NervesHub stores it encrypted with `SECRETS_ENCRYPTION_KEY` and never shows it again. Editing a channel leaves its URL as it was unless a new one is pasted in, which is how a channel is pointed at a workflow made again. Only URLs on Power Automate's hosts (`*.logic.azure.com` and `*.api.powerplatform.com`) are accepted.

## What is posted

A Teams channel can get the same events as a Slack channel:

| Event | Posted when |
| --- | --- |
| Health status changed | A device's health status moves, such as from healthy to warning. |
| Update failed | A device's update fails, stops reporting progress, or ends with the device back on its old firmware. |
| Update succeeded | A device finishes updating. |
| New error | A device reports an error not seen before in its product. |
| Error reopened | An error that was marked resolved happens again. |
| Workflow step started | A deployment group's workflow begins a step, or begins it again after somebody retries it. |
| Workflow waiting for approval | A workflow reaches a step that holds the rollout until somebody approves it. |
| Workflow step completed | Every device a step covers is on the release's firmware, or somebody approved an approval step. |
| Workflow step failed | Too many of a step's devices fail to update, and the rollout stops there. |
| Workflow step skipped | Somebody skips a step. |
| Product notifications | NervesHub adds something to a product's Notifications page. |

Events are held for 15 seconds, then posted as one Adaptive Card per kind of event, in the order each kind first happened. A single event gets a card of its own; a burst gets a count and the first ten devices. Device names, errors and deployment groups link to their pages in NervesHub, and a card about one device or deployment group has an **Open in NervesHub** button. Anything a device sent is shown as plain text, so it cannot become a link or formatting.

A Workflows webhook only posts. Its cards cannot carry buttons that act, so there is no Reboot, Approve or Retry as there is in Slack, and a card cannot be changed once posted. A workflow waiting for approval is approved on the deployment group's page, which its card links to.

**Send test message** posts a card to the channel straight away, saying what it will get.

## When posting fails

- If Teams refuses the webhook (the workflow was deleted or turned off, or its URL no longer works), NervesHub turns the channel off. Each product it was getting events for gets a notification saying why. Fix the workflow, then turn the channel back on, or edit it and paste the workflow's new URL.
- If Power Automate asks NervesHub to slow down, it waits as long as it is told.
- Any other failure is retried after 10 seconds, a minute and five minutes. What still could not be posted is tried again with the channel's next event.
- Events held for more than an hour are dropped rather than posted late.
