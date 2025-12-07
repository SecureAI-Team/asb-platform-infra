SET allow_experimental_object_type = 1;

CREATE DATABASE IF NOT EXISTS asb_events;

CREATE TABLE IF NOT EXISTS asb_events.security_events
(
    event_id UUID DEFAULT generateUUIDv4(),
    occurred_at DateTime DEFAULT now(),
    source String,
    subject String,
    action String,
    resource String,
    policy String,
    decision String,
    request_id String,
    metadata Object('json')
)
ENGINE = MergeTree
ORDER BY (occurred_at, event_id)
TTL occurred_at + INTERVAL 90 DAY DELETE
SETTINGS index_granularity = 8192;

