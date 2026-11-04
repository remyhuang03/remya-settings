//! Append-only observations. Missing observations are never inferred as sleep.
use rusqlite::{Connection, params};
use serde_json::{Value, json};
use std::{
    path::Path,
    time::{SystemTime, UNIX_EPOCH},
};
pub fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}
pub struct History {
    db: Connection,
    last: String,
    last_seen: i64,
    sampled: i64,
}
impl History {
    pub fn open(path: &Path) -> Result<Self, String> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        if path != Path::new(":memory:") {
            use std::os::unix::fs::OpenOptionsExt;
            std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .mode(0o600)
                .open(path)
                .map_err(|e| e.to_string())?;
        }
        let db = Connection::open(path).map_err(|e| e.to_string())?;
        db.busy_timeout(std::time::Duration::from_secs(2))
            .map_err(|e| e.to_string())?;
        db.execute_batch("PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS observations(id INTEGER PRIMARY KEY, time INTEGER NOT NULL, kind TEXT NOT NULL, value TEXT NOT NULL); CREATE INDEX IF NOT EXISTS observations_time ON observations(time,id);").map_err(|e|e.to_string())?;
        let mut h = Self {
            db,
            last: String::new(),
            last_seen: now(),
            sampled: 0,
        };
        h.record("session", json!("start"))?;
        Ok(h)
    }
    pub fn record(&mut self, kind: &str, value: Value) -> Result<(), String> {
        self.db
            .execute(
                "INSERT INTO observations(time,kind,value) VALUES(?1,?2,?3)",
                params![now(), kind, value.to_string()],
            )
            .map_err(|e| e.to_string())?;
        Ok(())
    }
    pub fn due(&self) -> bool {
        now() - self.sampled >= 60 || now() < self.sampled
    }
    pub fn sleeping(&mut self, sleeping: bool) -> Result<(), String> {
        self.record("state", json!(if sleeping { "sleep" } else { "unknown" }))?;
        self.last = if sleeping { "sleep" } else { "unknown" }.into();
        self.last_seen = now();
        Ok(())
    }
    pub fn observe(&mut self, state: &str, battery: Value) -> Result<(), String> {
        let time = now();
        if (time - self.last_seen > 5 && self.last != "sleep") || time < self.last_seen {
            self.record("gap", json!({"from":self.last_seen,"to":time}))?;
            self.last.clear();
        }
        if state != self.last {
            self.record("state", json!(state))?;
            self.last = state.into();
        }
        self.last_seen = time;
        if time - self.sampled >= 60 || time < self.sampled {
            self.record("battery", battery)?;
            self.sampled = time;
        }
        Ok(())
    }
    pub fn query(&self, request: &str) -> Result<Value, String> {
        #[derive(serde::Deserialize)]
        #[serde(deny_unknown_fields)]
        struct Query {
            from: i64,
            to: i64,
            #[serde(default)]
            after: i64,
            #[serde(default = "limit")]
            limit: u32,
        }
        fn limit() -> u32 {
            1000
        }
        let q: Query = serde_json::from_str(request).map_err(|e| e.to_string())?;
        if q.from > q.to || q.after < 0 || !(1..=1000).contains(&q.limit) {
            return Err("InvalidArgument: invalid history range or limit".into());
        }
        let mut stmt=self.db.prepare("SELECT id,time,kind,value FROM observations WHERE time>=?1 AND time<=?2 AND id>?3 ORDER BY id LIMIT ?4").map_err(|e|e.to_string())?;
        let rows=stmt.query_map(params![q.from,q.to,q.after,q.limit],|r|Ok(json!({"id":r.get::<_,i64>(0)?,"time":r.get::<_,i64>(1)?,"kind":r.get::<_,String>(2)?,"value":serde_json::from_str::<Value>(&r.get::<_,String>(3)?).unwrap_or(Value::Null)}))).map_err(|e|e.to_string())?;
        let items = rows
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| e.to_string())?;
        let mut context = vec![];
        if q.after == 0 {
            for kind in ["state", "session", "battery"] {
                let mut stmt=self.db.prepare("SELECT id,time,kind,value FROM observations WHERE time<?1 AND kind=?2 ORDER BY id DESC LIMIT 1").map_err(|e|e.to_string())?;
                let rows=stmt.query_map(params![q.from,kind],|r|Ok(json!({"id":r.get::<_,i64>(0)?,"time":r.get::<_,i64>(1)?,"kind":r.get::<_,String>(2)?,"value":serde_json::from_str::<Value>(&r.get::<_,String>(3)?).unwrap_or(Value::Null)}))).map_err(|e|e.to_string())?;
                context.extend(
                    rows.collect::<Result<Vec<_>, _>>()
                        .map_err(|e| e.to_string())?,
                );
            }
        }
        Ok(
            json!({"next":items.last().map(|v|v["id"].clone()),"observations":items,"context":context}),
        )
    }
}
impl Drop for History {
    fn drop(&mut self) {
        let _ = self.record("session", json!("stop"));
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn history_roundtrip() {
        let mut h = History::open(Path::new(":memory:")).unwrap();
        h.observe("screen-on", json!({"percentage":50})).unwrap();
        h.observe("screen-on", json!({"percentage":49})).unwrap();
        let v = h
            .query(&format!("{{\"from\":0,\"to\":{}}}", now() + 1))
            .unwrap();
        assert_eq!(v["observations"].as_array().unwrap().len(), 3);
        assert!(h.query("{\"from\":2,\"to\":1}").is_err());
    }
}

#[cfg(test)]
mod regression_tests {
    use super::*;
    #[test]
    fn sleep_is_not_a_gap_and_missing_observation_is() {
        let mut h = History::open(Path::new(":memory:")).unwrap();
        h.sleeping(true).unwrap();
        h.last_seen = now() - 3600;
        h.observe("screen-on", json!({"percentage":30})).unwrap();
        let count = |h: &History| {
            h.db.query_row(
                "SELECT count(*) FROM observations WHERE kind='gap'",
                [],
                |r| r.get::<_, i64>(0),
            )
            .unwrap()
        };
        assert_eq!(count(&h), 0);
        h.last_seen = now() - 100;
        h.observe("screen-off", Value::Null).unwrap();
        assert_eq!(count(&h), 1);
    }
    #[test]
    fn pagination_and_validation() {
        let mut h = History::open(Path::new(":memory:")).unwrap();
        h.record("state", json!("screen-on")).unwrap();
        let to = now() + 1;
        let first = h
            .query(&format!("{{\"from\":0,\"to\":{to},\"limit\":1}}"))
            .unwrap();
        let next = first["next"].as_i64().unwrap();
        let second = h
            .query(&format!("{{\"from\":0,\"to\":{to},\"after\":{next}}}"))
            .unwrap();
        assert_eq!(second["observations"].as_array().unwrap().len(), 1);
        assert!(h.query("{\"from\":0,\"to\":1,\"limit\":1001}").is_err());
        assert!(h.query("{\"from\":0,\"to\":1,\"extra\":1}").is_err());
    }
}
