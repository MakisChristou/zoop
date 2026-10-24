use std::fmt;

/// What the store was doing when it failed. Rendered into every `StorageError`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StoreOperation {
    Connect,
    Migrate,
    Ping,
    UpsertDevice,
    InsertRawFrame,
    FetchPendingFrames,
    MarkFrameDecoded,
    UpsertSample,
    InsertEvent,
    InsertEcgStrip,
    LatestSample,
    SamplesInRange,
    ListDevices,
    UpsertSleep,
    ListSleeps,
}

impl fmt::Display for StoreOperation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let name = match self {
            Self::Connect => "connect",
            Self::Migrate => "migrate",
            Self::Ping => "ping",
            Self::UpsertDevice => "upsert device",
            Self::InsertRawFrame => "insert raw frame",
            Self::FetchPendingFrames => "fetch pending frames",
            Self::MarkFrameDecoded => "mark frame decoded",
            Self::UpsertSample => "upsert sample",
            Self::InsertEvent => "insert event",
            Self::InsertEcgStrip => "insert ECG strip",
            Self::LatestSample => "read latest sample",
            Self::SamplesInRange => "read samples in range",
            Self::ListDevices => "list devices",
            Self::UpsertSleep => "upsert sleep",
            Self::ListSleeps => "list sleeps",
        };
        f.write_str(name)
    }
}
