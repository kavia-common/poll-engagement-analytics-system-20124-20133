-- Poll Engagement Analytics Database Schema
-- Centralized analytics schema for polling platform.
-- Tracks poll events, impressions, votes, metadata (user/session/device/platform), geo-location, and poll definitions.

-- USERS and SESSIONS
CREATE TABLE users (
    user_id UUID PRIMARY KEY,
    external_user_key TEXT, -- optionally map to external system
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sessions (
    session_id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(user_id) ON DELETE SET NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- DEVICE/PLATFORM INFO
CREATE TABLE device_platform (
    device_platform_id SERIAL PRIMARY KEY,
    device_type TEXT NOT NULL,   -- e.g., "mobile", "tablet", "web", "tv"
    os_name TEXT,                -- e.g., "iOS", "Android", "Windows", etc.
    os_version TEXT,
    browser_name TEXT,
    browser_version TEXT,
    app_version TEXT,
    platform_name TEXT,          -- e.g., "web", "mobile_app", "smart_tv"
    inserted_at TIMESTAMPTZ DEFAULT NOW()
);

-- POLL DEFINITIONS
CREATE TABLE polls (
    poll_id UUID PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    start_time TIMESTAMPTZ,
    end_time TIMESTAMPTZ,
    status TEXT, -- e.g., "active", "closed", etc.
    metadata JSONB
);

-- POLL OPTIONS
CREATE TABLE poll_options (
    option_id UUID PRIMARY KEY,
    poll_id UUID NOT NULL REFERENCES polls(poll_id) ON DELETE CASCADE,
    option_text TEXT NOT NULL,
    option_order INTEGER,
    metadata JSONB,
    UNIQUE(poll_id, option_order)
);

-- GEO-LOCATION
CREATE TABLE geo_location (
    geo_location_id SERIAL PRIMARY KEY,
    country_code CHAR(2),  -- ISO 3166-1 alpha-2
    region TEXT,
    city TEXT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION
);

-- EVENTS base table (event_type: 'impression', 'vote', 'view', etc.)
CREATE TABLE poll_events (
    event_id UUID PRIMARY KEY,
    poll_id UUID NOT NULL REFERENCES polls(poll_id) ON DELETE CASCADE,
    event_type TEXT NOT NULL, -- ENUM in production: 'impression', 'vote', etc.
    user_id UUID REFERENCES users(user_id) ON DELETE SET NULL,
    session_id UUID REFERENCES sessions(session_id) ON DELETE SET NULL,
    device_platform_id INT REFERENCES device_platform(device_platform_id) ON DELETE SET NULL,
    geo_location_id INT REFERENCES geo_location(geo_location_id) ON DELETE SET NULL,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    user_agent TEXT,
    ip_address INET, -- For geo lookups/unique counting
    metadata JSONB
);

-- IMPRESSIONS (each time a poll is shown to a user/session/device, possibly deduped)
CREATE TABLE poll_impressions (
    impression_id UUID PRIMARY KEY,
    poll_id UUID NOT NULL REFERENCES polls(poll_id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(user_id) ON DELETE SET NULL,
    session_id UUID REFERENCES sessions(session_id) ON DELETE SET NULL,
    device_platform_id INT REFERENCES device_platform(device_platform_id) ON DELETE SET NULL,
    geo_location_id INT REFERENCES geo_location(geo_location_id) ON DELETE SET NULL,
    impression_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    user_agent TEXT,
    ip_address INET,
    UNIQUE(poll_id, session_id, device_platform_id, COALESCE(user_id, '00000000-0000-0000-0000-000000000000'::uuid))
);

-- VOTES (event details for each poll vote)
CREATE TABLE poll_votes (
    vote_id UUID PRIMARY KEY,
    poll_id UUID NOT NULL REFERENCES polls(poll_id) ON DELETE CASCADE,
    option_id UUID NOT NULL REFERENCES poll_options(option_id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(user_id) ON DELETE SET NULL,
    session_id UUID REFERENCES sessions(session_id) ON DELETE SET NULL,
    device_platform_id INT REFERENCES device_platform(device_platform_id) ON DELETE SET NULL,
    geo_location_id INT REFERENCES geo_location(geo_location_id) ON DELETE SET NULL,
    vote_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    user_agent TEXT,
    ip_address INET,
    UNIQUE(poll_id, session_id, device_platform_id, COALESCE(user_id, '00000000-0000-0000-0000-000000000000'::uuid))
);

-- Indices for analytics performance
CREATE INDEX idx_poll_events_poll ON poll_events(poll_id);
CREATE INDEX idx_poll_events_type_time ON poll_events(event_type, occurred_at);
CREATE INDEX idx_impressions_poll ON poll_impressions(poll_id);
CREATE INDEX idx_votes_poll ON poll_votes(poll_id);
CREATE INDEX idx_votes_option ON poll_votes(option_id);
CREATE INDEX idx_user_id ON users(user_id);

-- Helper views (for rollups and analytics)
-- Example: Poll summary view (votes, impressions counts)
CREATE OR REPLACE VIEW poll_summary AS
SELECT
    p.poll_id,
    p.title,
    COUNT(DISTINCT i.impression_id) AS impressions,
    COUNT(DISTINCT v.vote_id) AS votes,
    COUNT(DISTINCT v.user_id) AS unique_voters
FROM polls p
LEFT JOIN poll_impressions i ON i.poll_id = p.poll_id
LEFT JOIN poll_votes v ON v.poll_id = p.poll_id
GROUP BY p.poll_id, p.title;
