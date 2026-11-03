use std::collections::VecDeque;

#[derive(Default)]
pub struct Log {
    lines: VecDeque<String>,
    current: String,
    escape: u8,
    carriage: bool,
}
impl Log {
    pub fn push(&mut self, text: &str) {
        for c in text.chars() {
            match self.escape {
                1 => {
                    self.escape = if c == '[' {
                        2
                    } else if c == ']' {
                        3
                    } else {
                        0
                    };
                    continue;
                }
                2 => {
                    if ('@'..='~').contains(&c) {
                        self.escape = 0;
                    }
                    continue;
                }
                3 => {
                    if c == '\u{7}' {
                        self.escape = 0;
                    } else if c == '\u{1b}' {
                        self.escape = 4;
                    }
                    continue;
                }
                4 => {
                    self.escape = if c == '\\' { 0 } else { 3 };
                    continue;
                }
                _ => {}
            }
            if self.carriage && c != '\n' && c != '\r' {
                self.current.clear();
            }
            self.carriage = false;
            match c {
                '\u{1b}' => self.escape = 1,
                '\r' => self.carriage = true,
                '\n' => {
                    self.lines.push_back(std::mem::take(&mut self.current));
                }
                '\u{8}' => {
                    self.current.pop();
                }
                '\t' if self.current.len() <= 4092 => self.current.push_str("    "),
                c if !c.is_control() && self.current.len() + c.len_utf8() <= 4096 => {
                    self.current.push(c)
                }
                _ => {}
            }
        }
        while self.lines.len() > 512
            || self.lines.iter().map(String::len).sum::<usize>() > 128 * 1024
        {
            self.lines.pop_front();
        }
    }
    pub fn lines(&self) -> Vec<String> {
        self.lines
            .iter()
            .cloned()
            .chain((!self.current.is_empty()).then(|| self.current.clone()))
            .collect()
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn terminal_progress_replaces_the_current_line_and_stays_bounded() {
        let mut log = Log::default();
        log.push("\x1b[32mDownloading 1%\x1b[0m\rDownloading 100%\r\nDone\n");
        assert_eq!(log.lines(), ["Downloading 100%", "Done"]);
        for _ in 0..1000 {
            log.push("next\n");
        }
        assert_eq!(log.lines().len(), 512);
        log.push(&"\t".repeat(10000));
        assert!(log.lines().last().unwrap().len() <= 4096);
    }
}
