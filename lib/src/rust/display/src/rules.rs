//! A strict reader and span-preserving editor for `monitors.lua`.
//!
//! Only `hl.monitor({ key = literal, ... })` statements and comments are accepted.
//! Anything else may be arbitrary Lua whose effect cannot be known, so writing is
//! refused instead of risking the user's file.
use std::ops::Range;

#[derive(Clone, Debug, PartialEq)]
pub struct Rule {
    pub output: String,
    /// Field names with their literal Lua source text, in file order.
    pub fields: Vec<(String, String)>,
    span: Range<usize>,
}

impl Rule {
    pub fn get(&self, field: &str) -> Option<String> {
        let raw = &self.fields.iter().rev().find(|(k, _)| k == field)?.1;
        Some(decode(raw))
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct RuleFile {
    pub text: String,
    pub rules: Vec<Rule>,
}

fn decode(raw: &str) -> String {
    let inner = raw.trim();
    if inner.starts_with('{') {
        let side = |name: &str| {
            inner
                .find(name)
                .and_then(|at| inner[at + name.len()..].split_once('='))
                .and_then(|(_, rest)| {
                    rest.trim()
                        .split(|c: char| !c.is_ascii_digit())
                        .next()
                        .map(str::to_owned)
                })
                .filter(|v| !v.is_empty())
                .unwrap_or_else(|| "0".into())
        };
        return ["top", "right", "bottom", "left"].map(side).join(" ");
    }
    if inner.len() >= 2 && (inner.starts_with('"') || inner.starts_with('\'')) {
        return inner[1..inner.len() - 1]
            .replace("\\\"", "\"")
            .replace("\\'", "'")
            .replace("\\\\", "\\");
    }
    inner.to_owned()
}

struct Scanner<'a> {
    text: &'a str,
    at: usize,
}

impl<'a> Scanner<'a> {
    fn rest(&self) -> &'a str {
        &self.text[self.at..]
    }
    fn line(&self) -> usize {
        self.text[..self.at].matches('\n').count() + 1
    }
    fn fail<T>(&self, what: &str) -> Result<T, String> {
        Err(format!("line {}: {what}", self.line()))
    }
    fn skip(&mut self) -> Result<(), String> {
        loop {
            let rest = self.rest();
            let trimmed = rest.trim_start();
            self.at += rest.len() - trimmed.len();
            if trimmed.starts_with("--[[") {
                let Some(end) = trimmed.find("]]") else {
                    return self.fail("unterminated comment");
                };
                self.at += end + 2;
            } else if trimmed.starts_with("--") {
                self.at += trimmed.find('\n').unwrap_or(trimmed.len());
            } else {
                return Ok(());
            }
        }
    }
    fn eat(&mut self, token: &str) -> bool {
        if self.rest().starts_with(token) {
            self.at += token.len();
            true
        } else {
            false
        }
    }
    fn string(&mut self) -> Result<(), String> {
        let quote = self.rest().chars().next().unwrap_or(' ');
        let bytes = self.text.as_bytes();
        let mut index = self.at + 1;
        while index < bytes.len() {
            match bytes[index] as char {
                '\\' => index += 2,
                '\n' => break,
                c if c == quote => {
                    self.at = index + 1;
                    return Ok(());
                }
                _ => index += 1,
            }
        }
        self.fail("unterminated string")
    }
    fn value(&mut self) -> Result<String, String> {
        let start = self.at;
        match self.rest().chars().next() {
            Some('"' | '\'') => self.string()?,
            Some('{') => {
                self.at += 1;
                loop {
                    self.skip()?;
                    match self.rest().chars().next() {
                        Some('}') => {
                            self.at += 1;
                            break;
                        }
                        Some('"' | '\'') => self.string()?,
                        Some(c) if c.is_alphanumeric() || "_=,.-;".contains(c) => {
                            self.at += c.len_utf8()
                        }
                        _ => return self.fail("unsupported table value"),
                    }
                }
            }
            _ => {
                let word = self
                    .rest()
                    .split(|c: char| !(c.is_alphanumeric() || c == '.' || c == '-'))
                    .next()
                    .unwrap_or("");
                if word != "true" && word != "false" && word.parse::<f64>().is_err() {
                    return self.fail("only literal values are supported");
                }
                self.at += word.len();
            }
        }
        Ok(self.text[start..self.at].to_owned())
    }
    fn rule(&mut self) -> Result<Rule, String> {
        let start = self.at;
        if !self.eat("hl.monitor") {
            return self.fail("only hl.monitor rules and comments are supported");
        }
        self.skip()?;
        if !self.eat("(") {
            return self.fail("expected (");
        }
        self.skip()?;
        if !self.eat("{") {
            return self.fail("expected a rule table");
        }
        let mut fields = vec![];
        loop {
            self.skip()?;
            if self.eat("}") {
                break;
            }
            let name = self
                .rest()
                .split(|c: char| !(c.is_alphanumeric() || c == '_'))
                .next()
                .unwrap_or("")
                .to_owned();
            if name.is_empty() {
                return self.fail("expected a field name");
            }
            self.at += name.len();
            self.skip()?;
            if !self.eat("=") {
                return self.fail("expected =");
            }
            self.skip()?;
            fields.push((name, self.value()?));
            self.skip()?;
            if !self.eat(",") && !self.eat(";") && !self.rest().starts_with('}') {
                return self.fail("expected , or }");
            }
        }
        self.skip()?;
        if !self.eat(")") {
            return self.fail("expected )");
        }
        let output = fields
            .iter()
            .find(|(k, _)| k == "output")
            .map(|(_, v)| decode(v));
        let Some(output) = output else {
            return self.fail("rule without output");
        };
        Ok(Rule {
            output,
            fields,
            span: start..self.at,
        })
    }
}

pub fn parse(text: &str) -> Result<RuleFile, String> {
    let mut scanner = Scanner { text, at: 0 };
    let mut rules = vec![];
    loop {
        scanner.skip()?;
        if scanner.rest().is_empty() {
            break;
        }
        if scanner.eat(";") {
            continue;
        }
        rules.push(scanner.rule()?);
    }
    Ok(RuleFile {
        text: text.to_owned(),
        rules,
    })
}

fn render(fields: &[(String, String)]) -> String {
    let body = fields
        .iter()
        .map(|(k, v)| format!("    {k} = {v}"))
        .collect::<Vec<_>>()
        .join(",\n");
    format!("hl.monitor({{\n{body}\n}})")
}

impl RuleFile {
    /// The rule Hyprland uses for this monitor: the last exact-name match, else the
    /// last `desc:` prefix match. The empty fallback rule never belongs to one output.
    pub fn find(&self, name: &str, description: &str) -> Option<&Rule> {
        self.rules
            .iter()
            .rev()
            .find(|r| r.output == name)
            .or_else(|| {
                self.rules.iter().rev().find(|r| {
                    r.output
                        .strip_prefix("desc:")
                        .is_some_and(|d| !d.is_empty() && description.starts_with(d))
                })
            })
    }

    /// Returns new file text with only this monitor's rule changed. `None` removes
    /// a field. A new rule starts from `initial` and is appended.
    pub fn with_changes(
        &self,
        name: &str,
        description: &str,
        initial: &[(String, String)],
        changes: &[(String, Option<String>)],
    ) -> String {
        let existing = self.find(name, description);
        let mut fields = existing.map(|r| r.fields.clone()).unwrap_or_else(|| {
            let mut fields = vec![("output".to_owned(), quote(name))];
            fields.extend_from_slice(initial);
            fields
        });
        for (key, value) in changes {
            match value {
                Some(value) => match fields.iter_mut().find(|(k, _)| k == key) {
                    Some(field) => field.1 = value.clone(),
                    None => fields.push((key.clone(), value.clone())),
                },
                None => fields.retain(|(k, _)| k != key),
            }
        }
        let rendered = render(&fields);
        match existing {
            Some(rule) => {
                let mut text = self.text.clone();
                text.replace_range(rule.span.clone(), &rendered);
                text
            }
            None => {
                let mut text = self.text.clone();
                if !text.is_empty() && !text.ends_with('\n') {
                    text.push('\n');
                }
                text.push_str(&rendered);
                text.push('\n');
                text
            }
        }
    }
}

pub fn quote(value: &str) -> String {
    format!("\"{}\"", value.replace('\\', "\\\\").replace('"', "\\\""))
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = r#"-- my displays
hl.monitor({
    output = "eDP-1",
    mode = "2560x1600@120.0",
    position = "0x1296",
    scale = "auto"
})
hl.monitor({ output = "desc:AOC U27", scale = 1.67, reserved_area = { top = 10, left = 2 } })
hl.monitor({ output = "", mode = "preferred" })
"#;

    #[test]
    fn reads_literals_and_tables() {
        let file = parse(SAMPLE).unwrap();
        assert_eq!(file.rules.len(), 3);
        let rule = file.find("eDP-1", "LG").unwrap();
        assert_eq!(rule.get("scale").unwrap(), "auto");
        let by_desc = file.find("DP-3", "AOC U27U3XD").unwrap();
        assert_eq!(by_desc.get("scale").unwrap(), "1.67");
        assert_eq!(by_desc.get("reserved_area").unwrap(), "10 0 0 2");
        assert!(file.find("HDMI-A-1", "other").is_none());
    }

    #[test]
    fn unknown_lua_is_refused_with_its_line() {
        for bad in [
            "if x then hl.monitor({output=\"a\"}) end",
            "hl.monitor(cfg)",
            "hl.monitor({output=name})",
            "hl.monitor({mode=\"preferred\"})",
            "hl.monitor({output=\"a\"}) os.execute(\"x\")",
            "hl.monitor({output=\"a\"",
        ] {
            assert!(parse(bad).is_err(), "{bad}");
        }
        assert!(parse("\n\nfoo()").unwrap_err().starts_with("line 3"));
    }

    #[test]
    fn edits_leave_comments_and_other_rules_untouched() {
        let file = parse(SAMPLE).unwrap();
        let text = file.with_changes(
            "eDP-1",
            "LG",
            &[],
            &[
                ("scale".into(), Some("1.6".into())),
                ("transform".into(), Some("1".into())),
                ("position".into(), None),
            ],
        );
        assert!(text.starts_with("-- my displays\nhl.monitor({\n    output = \"eDP-1\""));
        assert!(text.contains("hl.monitor({ output = \"desc:AOC U27\", scale = 1.67"));
        assert!(text.contains("hl.monitor({ output = \"\", mode = \"preferred\" })"));
        let again = parse(&text).unwrap();
        let rule = again.find("eDP-1", "LG").unwrap();
        assert_eq!(rule.get("scale").unwrap(), "1.6");
        assert_eq!(rule.get("transform").unwrap(), "1");
        assert_eq!(rule.get("position"), None);
    }

    #[test]
    fn new_outputs_are_appended_and_desc_rules_keep_their_match() {
        let file = parse(SAMPLE).unwrap();
        let text = file.with_changes(
            "HDMI-A-1",
            "x",
            &[("mode".into(), quote("preferred"))],
            &[("scale".into(), Some("2".into()))],
        );
        assert!(parse(&text).unwrap().find("HDMI-A-1", "x").is_some());
        let text = file.with_changes(
            "DP-3",
            "AOC U27U3XD",
            &[],
            &[("vrr".into(), Some("1".into()))],
        );
        let rule = parse(&text).unwrap();
        let rule = rule.find("DP-3", "AOC U27U3XD").unwrap();
        assert_eq!(rule.output, "desc:AOC U27");
        assert_eq!(rule.get("vrr").unwrap(), "1");
    }

    #[test]
    fn empty_file_gets_a_valid_rule() {
        let text = parse("").unwrap().with_changes("A", "", &[], &[]);
        assert_eq!(parse(&text).unwrap().rules[0].output, "A");
    }
}
