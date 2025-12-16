# Fletcher MVP: Location Context for AI Assistants

**Version:** 1.0 MVP  
**Target Launch:** 90 days from kickoff  
**Last Updated:** December 15, 2025

## Executive Summary

Fletcher is a privacy-first location tracking app that enables AI assistants to provide location-aware assistance through Model Context Protocol (MCP). The MVP focuses on a single, validated use case with one AI assistant integration to prove the core value proposition before expanding.

**MVP Goal:** Validate that users find value in giving their AI assistant location context, with measurable engagement and acceptable privacy comfort levels.

## What We're Building (MVP Scope)

### Core Product

**iOS-only mobile app** that:
- Tracks user location in the background with battery optimization
- Stores location history locally with encryption
- Exposes location data through an MCP server
- Provides granular privacy controls

**MCP Server** that:
- Implements Model Context Protocol standard (Anthropic spec)
- Provides real-time and historical location data
- Authenticates AI assistants with Pre-Shared MCP Tokens
- Logs all data access for user transparency

**Claude Integration** (primary launch partner):
- Users connect Fletcher to Claude via MCP
- Claude can access location context when answering questions
- Users control precision level shared with Claude

### Single Use Case Focus: "Travel Assistant"

Instead of trying to support all possible location use cases, MVP focuses exclusively on:

**"Get contextual help about where I am and where I'm going"**

Examples:
- "How long until I get to the airport?" (Claude knows current location + destination)
- "Find coffee shops near me" (Claude has real location, not IP-based guess)
- "What's the best route to avoid traffic?" (Claude sees current position)
- "Remind me to call Mom when I get home" (Claude can set location-based reminder)

This use case is:
✅ Immediately valuable  
✅ Easy to demonstrate  
✅ Privacy-comfortable (users already share location with Maps)  
✅ Measurable (we can track engagement)

## What We're NOT Building (Out of Scope for MVP)

**Explicitly excluded:**
- ❌ Android app (iOS only for MVP)
- ❌ Multi-assistant support (Claude only)
- ❌ Existing data import (Google Maps, Swarm, etc.)
- ❌ Social features or location sharing with other users
- ❌ Geofencing or automated triggers
- ❌ Journey predictions or ETA calculations (let AI handle this)
- ❌ Web dashboard or desktop app
- ❌ Precise indoor positioning
- ❌ Activity detection (walking/driving/etc.)

**These may come in v1.1+**, but MVP must prove core value first.

## Success Metrics (3-Month Post-Launch)

### Primary Metrics

**Adoption & Retention:**
- 500 active users (realistic for closed beta)
- 60% week-1 retention
- 40% month-1 retention
- 70% of active users have Fletcher connected to Claude

**Engagement:**
- Average 5+ location-aware queries per user per week
- 30%+ of Claude conversations use location context
- Users check app privacy logs at least weekly

**Technical Performance:**
- <5% daily battery drain attributable to Fletcher
- 95%+ location accuracy within 100m
- 99.9% MCP server uptime
- <500ms average API response time

**Privacy & Trust:**
- Net Promoter Score >30
- <10% churn due to privacy concerns
- Zero security incidents or data breaches

### Learning Metrics (Qualitative)

- Do users understand what data is being shared?
- What privacy controls do they actually use?
- What location-aware queries are most valuable?
- What concerns do they express about location sharing?
- Would they pay for this? How much?

## Technical Architecture

### Mobile App (iOS)

**Tech Stack:**
- Swift/SwiftUI (iOS 16+)
- CoreLocation for location tracking
- CoreData for local storage
- CryptoKit for encryption
- Sign in with Apple for auth

**Key Components:**

```
Fletcher/
├── Location/
│   ├── LocationManager.swift          # CoreLocation wrapper
│   ├── BackgroundLocationService.swift # Background tracking
│   └── BatteryOptimizer.swift         # Dynamic precision adjustment
├── Storage/
│   ├── LocationStore.swift            # CoreData persistence
│   ├── EncryptionService.swift        # AES-256 encryption
│   └── RetentionPolicy.swift          # Auto-deletion
├── MCP/
│   ├── MCPClient.swift                # Server communication
│   ├── AuthManager.swift              # API Key management
│   └── SyncService.swift              # Location upload
├── UI/
│   ├── MainView.swift                 # Map + status
│   ├── SettingsView.swift             # Privacy controls
│   ├── PrivacyLogView.swift           # Access transparency
│   └── OnboardingView.swift           # First-run experience
└── Models/
    ├── Location.swift                 # Data models
    ├── PrivacySettings.swift          # User preferences
    └── AccessLog.swift                # Audit trail
```

**Location Tracking Strategy:**

1. **Smart Precision Modes:**
   - High: GPS + WiFi triangulation (~10m accuracy)
   - Medium: Cell tower + WiFi (~100m accuracy)  
   - Low: Cell tower only (~1km accuracy)
   - Default: Medium (best battery/accuracy balance)

2. **Battery Optimization:**
   - Use significant location change API (iOS native)
   - Pause tracking when stationary for >15 minutes
   - Reduce precision when battery <20%
   - Stop tracking when battery <10%

3. **Background Behavior:**
   - Request "Always" location permission with clear explanation
   - Batch location updates (upload every 5 minutes, not real-time)
   - Use background tasks API for efficient syncing
   - Display blue status bar indicator (iOS requirement)

**Local Storage:**

```swift
// CoreData Entity
LocationPoint {
    id: UUID
    latitude: Double
    longitude: Double
    accuracy: Double
    timestamp: Date
    encryptedData: Data  // Additional metadata
    syncedToServer: Bool
    createdAt: Date
}
```

- Encrypt all location data using device keychain
- Store up to 30 days locally (user configurable: 7/14/30/90 days)
- Auto-purge based on retention policy
- ~5MB storage for 30 days at 5-minute intervals

### MCP Server

**Tech Stack:**
- Node.js (TypeScript)
- Fastify web framework
- PostgreSQL with PostGIS extension
- Redis for caching
- Deploy on Railway/Render (simple, affordable)

**API Endpoints (MCP Standard):**

```typescript
// MCP Resource Endpoints
GET  /mcp/resources/current-location
GET  /mcp/resources/location-history?start={timestamp}&end={timestamp}
GET  /mcp/resources/favorite-places

// MCP Tools (callable by AI)
POST /mcp/tools/find-nearby
POST /mcp/tools/calculate-eta
POST /mcp/tools/get-directions

// Admin/Management
POST /api/mcp/generate-token
GET  /api/mcp/tokens
DELETE /api/mcp/tokens/:id
GET  /api/access-logs
```

**Database Schema:**

```sql
-- Users table
users (
    id UUID PRIMARY KEY,
    apple_id TEXT UNIQUE,
    created_at TIMESTAMP,
    privacy_settings JSONB,
    retention_days INTEGER DEFAULT 30
)

-- Location history (time-series optimized)
locations (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    point GEOGRAPHY(POINT, 4326),  -- PostGIS type
    accuracy FLOAT,
    timestamp TIMESTAMP,
    created_at TIMESTAMP,
    INDEX idx_user_time (user_id, timestamp DESC)
)

-- AI assistant access
assistant_connections (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    assistant_type TEXT,  -- 'claude'
    mcp_token TEXT,       -- Bearer token
    token_name TEXT,      -- User label
    connected_at TIMESTAMP,
    expires_at TIMESTAMP
)

-- Access audit log
access_logs (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    assistant_type TEXT,
    endpoint TEXT,
    timestamp TIMESTAMP,
    location_count INTEGER,
    precision_shared TEXT
)
```

**MCP Implementation:**

Following Anthropic's Model Context Protocol specification:

```typescript
// MCP Server Response Format
{
  "resources": [
    {
      "uri": "fletcher://location/current",
      "name": "Current Location",
      "description": "User's most recent location",
      "mimeType": "application/json"
    }
  ],
  "tools": [
    {
      "name": "find_nearby",
      "description": "Find places near user's location",
      "inputSchema": {
        "type": "object",
        "properties": {
          "category": { "type": "string" },
          "radius_meters": { "type": "number" }
        }
      }
    }
  ]
}

// Location Resource Response
{
  "type": "geojson",
  "geometry": {
    "type": "Point",
    "coordinates": [-122.4194, 37.7749]
  },
  "properties": {
    "accuracy": 15.0,
    "timestamp": "2025-12-14T17:30:00Z",
    "precision_level": "medium"
  }
}
```

**Security:**

- API Keys for mobile app authentication
- Pre-shared Bearer tokens for MCP access
- Rate limiting: 60 requests/minute per assistant
- Request signing to prevent replay attacks
- Audit log of every data access
- Automatic token rotation every 30 days

**Privacy Controls:**

Users can configure per-assistant:
- Precision level (high/medium/low)
- Historical data access (none/1hr/24hr/7days/30days)
- Pause sharing (temporary disable)
- Revoke access (permanent disconnect)

### Claude Integration

**Setup Flow:**

1. User opens Fletcher app to generate token
2. Copies token and MCP URL
3. Opens Claude Desktop settings → Integrations
4. Clicks "Add MCP Server"
5. Enters URL and pasted token
6. Connection established immediately

**Claude Usage:**

```
User: "How long until I get to SFO airport?"

[Claude uses Fletcher MCP to get current location]
[Claude calculates ETA using current location + traffic data]

Claude: "You're currently in Hayes Valley. With current traffic,
it'll take about 35 minutes to reach SFO. You should leave in 
the next 10 minutes to arrive by your 3pm deadline."
```

**Data Shared with Claude:**

Based on user's precision setting:
- **High:** Exact coordinates + 30 days history
- **Medium:** ~100m accuracy + 7 days history  
- **Low:** City-level + current day only

## User Experience

### Onboarding (Critical for MVP)

**Step 1: Value Proposition**
- "Give Claude your location context"
- Show 3 example use cases with screenshots
- Emphasize privacy controls

**Step 2: Permissions**
- Request "Always" location access
- Clear explanation of why (background tracking)
- Show iOS privacy indicators

**Step 3: Privacy Setup**
- Choose precision level (default: Medium)
- Set retention period (default: 30 days)
- Review what data is stored

**Step 4: Connect Claude**
- Generate MCP Token
- Copy-paste into Claude
- Success confirmation

**Total time:** <3 minutes

### Main App Interface

**Main App Interface:**
- Live map showing current location
- Last 24 hours location trail (faded)
- Battery impact indicator
- **Active/paused status toggle (Manual override)**
- **Manual Zoom Controls (+/- buttons)**
- **Visual Feedback:** "TRACKING OFF" overlay when disabled
- **History View**: Toggle between list and map view of location history

**Settings View:**
- Precision level slider
- Retention period selector
- Connected assistants list
- Privacy log access
- Emergency "Pause All" button

**Privacy Log View:**
- Timeline of all AI assistant queries
- What data was shared
- Which assistant made the request
- Timestamp and location

### Key User Flows

**Daily Use:**
1. User opens Claude
2. Asks location-aware question
3. Claude uses Fletcher MCP to get location
4. Claude provides contextual answer
5. User checks Fletcher privacy log (optional)

**Privacy Review:**
1. User opens Fletcher weekly
2. Reviews access log
3. Sees what Claude requested
4. Adjusts precision if uncomfortable
5. Continues using or disconnects

**Pause Tracking:**
1. User wants privacy for sensitive location
2. Opens Fletcher
3. Taps "Pause All Tracking"
4. Location tracking stops immediately
5. Resumes manually or auto-resumes in 24hrs

## Privacy & Compliance

### Privacy Principles

1. **Transparency:** Users see every data access in real-time
2. **Control:** Granular settings for precision and retention
3. **Minimization:** Collect only what's needed for the use case
4. **Security:** Encryption at rest and in transit
5. **Deletion:** Easy data export and complete deletion

### Legal Compliance (MVP)

**Must Have:**
- ✅ Privacy Policy (GDPR/CCPA compliant)
- ✅ Terms of Service
- ✅ User consent flows
- ✅ Data deletion on request (<30 days)
- ✅ Breach notification plan
- ✅ Data Processing Agreement with hosting provider

**Geographic Restrictions (MVP):**
- Launch in US only (CCPA compliance)
- Add EU/UK in v1.1 (GDPR compliance)
- Exclude China, Russia (different regulations)

### Data Handling

**What We Store:**
- Location coordinates (encrypted)
- Timestamps
- Accuracy metadata
- User privacy settings
- Access logs

**What We DON'T Store:**
- Place names or addresses (derived client-side only)
- Contacts or relationships
- Photos or media
- Financial information
- Health data

**Data Retention:**
- User data: User-configurable (7-90 days)
- Access logs: 90 days minimum
- Account data: Until deletion request

**Third Parties:**
- Apple (Sign in with Apple)
- Hosting provider (Railway/Render)
- AI assistants (Claude only for MVP)
- NO advertising networks
- NO analytics beyond first-party

## Go-to-Market Strategy

### Launch Plan: Closed Beta

**Month 1: Friends & Family (50 users)**
- Personal network recruitment
- High-touch feedback sessions
- Rapid iteration on UX/privacy concerns

**Month 2: Public Beta (250 users)**
- TestFlight signup page
- Post on relevant communities (r/ClaudeAI, HN)
- Emphasize privacy-first positioning
- Gather quantitative metrics

**Month 3: Feedback & Refinement (500 users)**
- Analyze usage patterns
- User interviews (20+ people)
- Decide on v1.1 features
- Evaluate monetization options

### Marketing Message

**Core Positioning:**
"Give your AI assistant location context, without giving up privacy"

**Key Differentiators:**
- Privacy-first (vs. Google/Apple data collection)
- Transparent (see every data access)
- AI-native (built for assistants, not humans)
- Simple (one use case, done well)

**Target Audience:**
- Claude power users
- Privacy-conscious tech professionals
- Early adopters in AI space
- Age 25-45, tech-savvy

### Distribution

**Primary Channels:**
- TestFlight (closed beta)
- App Store (public launch)
- Direct link from Claude integration docs

**Marketing Channels:**
- Product Hunt launch
- Hacker News "Show HN"
- Reddit (r/ClaudeAI, r/privacy)
- Twitter/X (AI influencer outreach)
- Anthropic partnership (Claude blog post)

## Development Roadmap

### Sprint 1-2 (Weeks 1-4): Foundation
- [ ] iOS project setup with SwiftUI
- [ ] CoreLocation integration with background tracking
- [ ] Local CoreData storage with encryption
- [ ] Basic map UI showing current location
- [ ] Battery optimization implementation

### Sprint 3-4 (Weeks 5-8): MCP Server
- [x] Node.js server with Fastify
- [x] PostgreSQL + PostGIS setup
- [x] MCP protocol implementation
- [x] API Key & MCP Token authentication
- [x] Current location endpoint
- [x] Location history endpoint

### Sprint 5-6 (Weeks 9-12): Integration
- [ ] iOS ↔ Server sync implementation
- [ ] Claude MCP connection flow
- [ ] Privacy settings UI
- [ ] Access log UI
- [ ] Onboarding flow
- [ ] App Store submission

### Sprint 7 (Week 13): Beta Launch
- [ ] TestFlight setup
- [ ] Friends & family recruitment
- [ ] Feedback collection system
- [ ] Bug fixes and polish
- [ ] Privacy policy and legal docs

### Sprint 8-9 (Weeks 14-18): Iteration
- [ ] User feedback implementation
- [ ] Performance optimization
- [ ] Expanded beta (250 users)
- [ ] Metrics dashboard
- [ ] User interviews

### Sprint 10-12 (Weeks 19-24): Public Launch
- [ ] App Store review process
- [ ] Marketing materials
- [ ] Public launch (500 users)
- [ ] Monitor metrics
- [ ] Plan v1.1 features

## Budget & Resources

### Team Requirements

**Minimum Viable Team:**
- 1x iOS Developer (primary)
- 1x Backend Developer (primary)
- 0.5x Designer (contract)
- 0.25x Legal/Privacy (contract)
- 1x Product Manager (you)

**Total:** ~2.75 FTE for 6 months

### Technology Costs (Monthly)

- Railway/Render hosting: $50
- PostgreSQL database: $25
- Domain + SSL: $5
- Apple Developer account: $8/mo ($99/year)
- TestFlight: Free
- Total: ~$90/month

### One-Time Costs

- Legal review (privacy policy, TOS): $2,000
- Design (logo, app icon, screens): $3,000
- App Store assets: $500
- Total: ~$5,500

**6-Month MVP Budget: ~$6,000 + team salaries**

## Risk Assessment

### High-Risk Items

**1. iOS App Store Rejection**
- **Risk:** Apple rejects due to location tracking concerns
- **Mitigation:** Follow Apple guidelines strictly, clear user communication, privacy-first positioning
- **Plan B:** Focus on TestFlight beta while appealing

**2. Poor Battery Life**
- **Risk:** Users uninstall due to battery drain
- **Mitigation:** Extensive battery testing, multiple precision modes, automatic throttling
- **Success Criteria:** <5% daily battery impact

**3. Privacy Concerns**
- **Risk:** Users don't trust the app with location
- **Mitigation:** Transparency, open-source consideration, privacy logs, strong messaging
- **Plan B:** Consider open-sourcing core components

**4. Low Engagement**
- **Risk:** Users connect but don't actually use location features
- **Mitigation:** User research before building, clear use case demonstrations
- **Kill Switch:** <30% weekly engagement → pivot or shut down

### Medium-Risk Items

**5. MCP Adoption**
- **Risk:** MCP protocol not widely adopted by AI assistants
- **Mitigation:** Start with Claude (guaranteed support), plan for standard REST API fallback
- **Plan B:** Build REST API alongside MCP

**6. Competition**
- **Risk:** Apple/Google/Anthropic builds this feature natively
- **Mitigation:** Move fast, focus on privacy differentiation, consider partnership
- **Plan B:** Pivot to B2B or different use case

**7. Regulatory Changes**
- **Risk:** New laws restrict location tracking apps
- **Mitigation:** Conservative legal interpretation, monitor legislation
- **Plan B:** Geographic restrictions or feature limitations

## Open Questions (Requires User Research)

### Before Development Starts

1. **Will users actually use this?**
   - Run survey with 100+ Claude users
   - Ask: "Would you give Claude access to your location?"
   - Target: >60% say "yes" or "maybe"

2. **What's the privacy comfort level?**
   - Show mockups of privacy controls
   - Ask: "What would make you comfortable?"
   - Identify must-have privacy features

3. **What use cases matter most?**
   - Present 10 location-aware scenarios
   - Ask users to rank by value
   - Validate our "travel assistant" focus

### During Beta

4. **What precision level do users choose?**
   - Default to medium, track selections
   - Interview users about their choice
   - Adjust defaults based on data

5. **How often do they check privacy logs?**
   - Track log access frequency
   - Understand privacy verification behavior
   - Optimize UI based on usage

6. **Would they pay for this?**
   - A/B test pricing messaging
   - Van Westendorp price sensitivity survey
   - Determine monetization model for v1.1

## Success Criteria for MVP

**Ship Decision (After 3 months beta):**

✅ **SHIP v1.0 if:**
- 60%+ week-1 retention
- 40%+ location-aware query usage
- NPS >30
- <5% battery impact
- Zero critical security issues

⚠️ **PIVOT if:**
- <40% week-1 retention
- <20% location-aware query usage
- NPS <10
- Significant privacy concerns
- Users not understanding value

❌ **KILL if:**
- <20% week-1 retention
- <10% location-aware query usage
- Regulatory blockers
- Unfixable technical issues
- No path to monetization

## Next Steps

### Immediate (Week 1)

1. **User Validation:**
   - Create survey for Claude users
   - Post in r/ClaudeAI for feedback
   - Run 5-10 user interviews
   - **Go/No-Go decision based on results**

2. **Technical Validation:**
   - Prototype basic iOS location tracking
   - Test battery impact
   - Review Apple guidelines
   - Validate MCP specification

3. **Team Assembly:**
   - Recruit iOS developer
   - Recruit backend developer
   - Contract designer
   - Contract privacy lawyer

### Week 2-4 (If validation passes)

- Finalize MVP spec
- Create detailed technical architecture
- Set up development environments
- Begin Sprint 1 development

---

**Document Status:** Ready for validation  
**Next Review:** After user research completion  
**Owner:** [Product Manager]  
**Stakeholders:** [Engineering, Design, Legal]
