# Rokid Teams HUD


> **🔵 Connectivity Update — May 2025**
> The glasses connection has been migrated from **raw TCP sockets** to
> **Bluetooth via the Rokid AI glasses SDK** (`pod 'RokidSDK' ~> 1.10.2`).
> No Wi-Fi port forwarding is needed. See **SDK Setup** below.

iOS app that bridges **Microsoft Teams** with **Rokid AR glasses** — see your messages, meetings, and presence on your heads-up display in real time.

```
👓 Glasses query / 📱 iPhone monitor
         ↓
  iPhone (RokidTeams)
         ↓  Microsoft Graph API v1.0
  graph.microsoft.com
         ↓  messages · meetings · presence
  iPhone ──Bluetooth/RokidSDK──▶ Rokid Glasses (live HUD)
```

## What appears on the glasses

```
🟢 Available
💬 4 recent messages
📅 Weekly Standup in 8m  2:00 PM – 2:30 PM
💬 Sarah: Can you review the PR before EOD?
```

Instant alerts fire on your glasses for:
- New **direct messages** from colleagues
- **@mentions** in channels
- **Urgent** marked messages
- Meetings starting in the next N minutes (configurable)

## Glasses → Phone commands (TCP :8098)

| Command | Result |
|---------|--------|
| `QUERY: messages` | Show recent messages from all chats |
| `QUERY: meetings` | Show today's full schedule |
| `QUERY: next` | Show the next upcoming meeting |
| `QUERY: status` | Show your current presence/activity |
| `QUERY: unread` | Push current summary |
| `QUERY: presence John` | Look up John's last activity |
| `QUERY: refresh` | Reload from Microsoft Graph |

Plain text also triggers the default summary.

## Phone → Glasses packet types

```json
{"type":"teams",    "text":"🟢 Available\n💬 4 recent  📅 Standup in 8m"}
{"type":"alert",    "text":"💬 NEW @you\n💬 Sarah: Can you review the PR?"}
{"type":"meeting",  "text":"📅 Starting in 5 min: Weekly Standup\n2:00 PM – 2:30 PM"}
{"type":"messages", "text":"💬 Sarah (2m ago): Can you review..."}
{"type":"meetings", "text":"🟡 Standup @ 2:00–2:30 PM\n📅 Review @ 4:00–5:00 PM"}
{"type":"presence", "text":"🔴 John Smith · In a meeting"}
{"type":"status",   "text":"🔍 Looking up John…"}
{"type":"error",    "text":"❌ Session expired"}
```

## Setup

### Step 1 — Register an Azure App (free, one-time)

1. Go to [portal.azure.com](https://portal.azure.com) → **Azure Active Directory** → **App registrations** → **New registration**
2. Name it anything (e.g. "Rokid Teams HUD")
3. Under **Supported account types** choose: *Accounts in any organizational directory and personal Microsoft accounts*
4. Under **Redirect URI** → Platform: **Mobile and desktop applications** → enter: `rokidteams://auth`
5. Click **Register**
6. Copy the **Application (client) ID** — you'll paste this in Settings

### Step 2 — Grant API permissions

In your app registration → **API permissions** → **Add a permission** → **Microsoft Graph** → **Delegated**:
- `User.Read`
- `Chat.Read`
- `Presence.Read`
- `Presence.Read.All`
- `Calendars.Read`
- `offline_access`

Click **Grant admin consent** if you're an admin, or ask your IT admin to grant consent.

### Step 3 — Build and run

1. Open `RokidTeams.xcodeproj` in Xcode 15+
2. Set your team in Signing & Capabilities
3. Build and run on iPhone (iOS 17+)
4. In **Settings**: paste your Client ID, set Tenant ID (use `common` for personal accounts)
5. Tap **Sign in with Microsoft** on the Teams tab
6. Connect Rokid glasses to the same Wi-Fi; point TCP client at `<phone-ip>:8098`

## Microsoft Graph API

Uses [Microsoft Graph v1.0](https://learn.microsoft.com/en-us/graph/overview) with PKCE OAuth2:

| Feature | Graph endpoint |
|---------|---------------|
| Sign in | `https://login.microsoftonline.com/{tenant}/oauth2/v2.0/authorize` |
| My profile | `GET /me` |
| My chats | `GET /me/chats?$expand=lastMessagePreview,members` |
| Chat messages | `GET /me/chats/{id}/messages` |
| My presence | `GET /me/presence` |
| Today's meetings | `GET /me/calendarView?startDateTime=...&endDateTime=...` |
| Joined Teams | `GET /me/joinedTeams` |

## Display formats

| Format | Glasses output |
|--------|----------------|
| **Compact** | Presence + unread count + next meeting + latest message |
| **Detailed** | Full message text + meeting details for top items |
| **Minimal** | Unread count and presence only |

## Requirements

- iOS 17.0+
- Xcode 15+
- Microsoft account (personal or work/school)
- Azure App Registration (free — see Setup above)
- Rokid AR glasses on the same Wi-Fi (optional — app works standalone as a Teams dashboard)
