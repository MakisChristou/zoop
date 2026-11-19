//! Stable workout identities and revisioned correction commands. Metrics are a
//! replaceable projection; user intent never lives in the detector candidate table.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, types::Json};

/// Measured summaries. Missing readings remain absent rather than becoming zero.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct SessionMetrics {
    /// Sleep-specific projection; absent for workouts.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sleep: Option<serde_json::Value>,
    pub load: Option<f64>,
    pub avg_hr: Option<f64>,
    pub max_hr: Option<i16>,
    pub trimp: Option<f64>,
    pub zones_min: Option<Vec<i32>>,
    pub kcal: Option<f64>,
    pub steps: Option<i64>,
    pub coverage_s: Option<i64>,
    pub hr_coverage_s: Option<i64>,
}

/// An effective workout, including removed/replaced records for old links and undo.
#[derive(Debug, Clone, FromRow, Serialize, Deserialize)]
pub struct WorkoutSession {
    pub id: i64,
    pub start_ts: DateTime<Utc>,
    pub end_ts: DateTime<Utc>,
    pub duration_s: i64,
    pub kind: String,
    pub detected_kind: String,
    pub edited: bool,
    pub fixed: bool,
    pub auto_detected: bool,
    pub notification_eligible: bool,
    pub revision: i64,
    pub status: String,
    pub last_edit: Option<String>,
    pub replacements: Vec<i64>,
    #[serde(flatten)]
    pub metrics: Json<SessionMetrics>,
    pub metrics_pending: bool,
    pub timezone: String,
}

/// The revision seen by an editor; stale forms cannot silently overwrite a change.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionRevision {
    pub id: i64,
    pub revision: i64,
}

/// Explicit, half-open workout bounds in UTC.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionInterval {
    pub start_ts: DateTime<Utc>,
    pub end_ts: DateTime<Utc>,
    pub kind: String,
}

/// An idempotent command. Merge and split validate their complete input/output set.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkoutCorrection {
    pub operation_id: String,
    pub action: String,
    #[serde(default)]
    pub targets: Vec<SessionRevision>,
    #[serde(default)]
    pub intervals: Vec<SessionInterval>,
    pub undo_id: Option<String>,
}

/// Identifies saved records even if a retried command has since been superseded.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CorrectionReceipt {
    pub operation_id: String,
    pub workout_ids: Vec<i64>,
}

/// Calculation ready for transactional publication. Fixed sessions carry their id.
#[derive(Debug, Clone)]
pub struct SessionCalculation {
    pub id: Option<i64>,
    pub start_ts: DateTime<Utc>,
    pub end_ts: DateTime<Utc>,
    pub kind: String,
    pub metrics: SessionMetrics,
}

/// Persisted ownership of an interval prevents removed or trimmed fragments returning.
#[derive(Debug, Clone, FromRow)]
pub struct CorrectionScope {
    pub start_ts: DateTime<Utc>,
    pub end_ts: DateTime<Utc>,
}

/// Separate namespaces sharing correction concurrency and reset semantics.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SessionDomain {
    Workout,
    Sleep,
}
impl SessionDomain {
    pub(crate) const fn sessions(self) -> &'static str {
        match self {
            Self::Workout => "workout_sessions",
            Self::Sleep => "sleep_sessions",
        }
    }
    pub(crate) const fn corrections(self) -> &'static str {
        match self {
            Self::Workout => "workout_corrections",
            Self::Sleep => "sleep_corrections",
        }
    }
    pub(crate) const fn aliases(self) -> &'static str {
        match self {
            Self::Workout => "workout_aliases",
            Self::Sleep => "sleep_aliases",
        }
    }
    pub(crate) const fn sequence(self) -> &'static str {
        match self {
            Self::Workout => "workouts_id_seq",
            Self::Sleep => "sleep_session_ids",
        }
    }
    pub(crate) const fn kind(self) -> &'static str {
        match self {
            Self::Workout => "workout",
            Self::Sleep => "sleep",
        }
    }
    pub(crate) fn valid_kind(self, kind: &str) -> bool {
        match self {
            Self::Workout => matches!(kind, "walk" | "resistance" | "activity"),
            Self::Sleep => matches!(kind, "main" | "nap"),
        }
    }
}
