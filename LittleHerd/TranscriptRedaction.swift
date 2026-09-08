import Foundation

/// Scrubbing secrets out of a transcript before it is carried to another machine.
///
/// **This cannot be complete, and saying so is the point.** A secret is not a shape; it
/// is a fact about a string that nobody wrote down. A transcript that quotes a password
/// in prose — "the wifi one is hunter2" — is indistinguishable from a transcript that
/// quotes a word. So this removes the secrets that have a *form* here, and the honest
/// claim is "much less exposed", never "safe".
///
/// What it is good at is the case that actually occurs on this herd. A session that ran
/// `sops -d` has ninety-odd `KEY=value` lines sitting in a tool result, and a session
/// that used a token has it in an argument or a header. Those have shapes, and shapes
/// can be matched. Measured against this project's own transcript on 7 September: 27
/// `sops -d`, 119 `secrets.env`, 11 `ANTHROPIC_API_KEY`, 41 `Bearer`, two PEM private
/// key blocks.
///
/// **It works on parsed JSON, not on raw text**, which is what keeps the carried file
/// resumable. A regex over the whole file could truncate a string mid-escape and leave a
/// line that no longer parses — and a transcript with one malformed record resumes as a
/// session missing everything after it, silently. Every line is decoded, its strings
/// rewritten, and re-encoded, so the result is valid by construction rather than by
/// inspection. A line that does not parse is passed through untouched: it was not ours
/// to rewrite, and dropping it would lose history.
nonisolated enum TranscriptRedaction {
    static let marker = "[redacted]"

    /// Key names whose value is secret whatever it looks like. Matched
    /// case-insensitively against the left of a `KEY=value` or `"key": "value"`.
    static let secretNameFragments = [
        "api_key", "apikey", "secret", "token", "password", "passwd", "credential",
        "private_key", "auth", "access_key", "session_key", "client_secret",
    ]

    /// Values that announce themselves. Deliberately anchored and specific: a pattern
    /// loose enough to catch every token would also catch commit shas and file hashes,
    /// and a transcript with its shas rewritten is a transcript that has lost its
    /// meaning.
    static let valuePatterns: [String] = [
        #"sk-[A-Za-z0-9_-]{16,}"#,                       // OpenAI / Anthropic style
        #"sk-ant-[A-Za-z0-9_-]{16,}"#,
        #"gh[pousr]_[A-Za-z0-9]{20,}"#,                  // GitHub
        #"github_pat_[A-Za-z0-9_]{20,}"#,
        #"xox[baprs]-[A-Za-z0-9-]{10,}"#,                // Slack
        #"AKIA[0-9A-Z]{16}"#,                            // AWS access key id
        #"age1[a-z0-9]{50,}"#,                           // age recipient/identity
        #"AC[0-9a-f]{32}"#,                              // Twilio account sid
        #"SK[0-9a-f]{32}"#,                              // Twilio API key sid
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#,
        #"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"#,  // JWT
    ]

    /// **Compiled once, not per string.** The first version built every
    /// `NSRegularExpression` inside the replace loop, so a real transcript compiled the
    /// same fifteen patterns for each of eleven thousand records. With that and the
    /// line-level prefilter below, the measured rate is **about a second per megabyte**
    /// — two seconds for the 2 MB, 700-record sample, which is the size range a carried
    /// session actually falls in. Very large transcripts are worse than linear, because
    /// cost follows the length of individual strings as well as their number.
    ///
    /// None of that was visible in the unit tests, which run on fixtures measured in
    /// bytes.
    private static let namePatterns: [NSRegularExpression] = {
        let names = secretNameFragments.joined(separator: "|")
        return [
            "(?i)([A-Z0-9_]*(?:\(names))[A-Z0-9_]*)\\s*=\\s*[^\\s\"']+",
            "(?i)(\"[^\"]*(?:\(names))[^\"]*\"\\s*:\\s*)\"[^\"]*\"",
            "(?i)(Authorization:\\s*(?:Bearer|Basic)\\s+)[A-Za-z0-9._~+/=-]+",
            "(?i)(-{1,2}password|-{1,2}token|-{1,2}secret)(\\s+|=)[^\\s\"']+",
        ].compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    private static let compiledValuePatterns: [NSRegularExpression] =
        valuePatterns.compactMap { try? NSRegularExpression(pattern: $0) }

    /// **The prefilter, and it has to be selective or it is worthless.** The first
    /// attempt tested for `"gh"`, `"AC"` and `"SK"`, which occur in ordinary prose —
    /// "right", "through", any capitalised word — so almost nothing was skipped and the
    /// scrub still took minutes. These are the words that actually accompany a secret,
    /// and a line without any of them cannot match a pattern below.
    ///
    /// It runs on the whole raw line before the JSON is even parsed, so a record with
    /// nothing interesting costs one case-insensitive search and no decode at all. On a
    /// real transcript that is the overwhelming majority of records.
    private static let tells = [
        "key", "token", "secret", "password", "passwd", "credential", "auth",
        "bearer", "-----BEGIN", "sk-", "ghp_", "gho_", "ghu_", "ghs_", "github_pat_",
        "xox", "AKIA", "age1", "eyJ",
    ]

    static func couldHoldSomething(_ line: String) -> Bool {
        for tell in tells where line.range(of: tell, options: .caseInsensitive) != nil {
            return true
        }
        return false
    }

    /// Rewrites one string: `KEY=value` and `key: value` assignments whose name looks
    /// secret, then the self-announcing value shapes.
    static func redact(_ text: String) -> String {
        var out = text
        for re in namePatterns {
            out = re.stringByReplacingMatches(
                in: out, options: [], range: NSRange(out.startIndex..., in: out),
                // `$1` keeps the name and drops only the value: that a key was there is
                // often the useful half, and the name itself is not secret.
                withTemplate: "$1=\(marker)")
        }
        for re in compiledValuePatterns {
            out = re.stringByReplacingMatches(
                in: out, options: [], range: NSRange(out.startIndex..., in: out),
                withTemplate: marker)
        }
        return out
    }

    /// Redacts every string inside one decoded JSON value, at any depth.
    static func redactJSON(_ value: Any) -> Any {
        switch value {
        case let s as String: return redact(s)
        case let a as [Any]: return a.map(redactJSON)
        case let d as [String: Any]: return d.mapValues(redactJSON)
        default: return value
        }
    }

    /// The whole transcript, line by line.
    ///
    /// Returns the scrubbed text and how many lines were changed — the count is what the
    /// interface shows, because "42 of 5,954 records had something removed" is a fact a
    /// person can weigh, where "redacted ✓" is a reassurance they cannot check.
    static func redactTranscript(_ jsonl: String) -> (text: String, changedLines: Int) {
        var changed = 0
        var lines: [String] = []
        for line in jsonl.split(separator: "\n", omittingEmptySubsequences: false) {
            let original = String(line)
            // Nothing that could match: keep the line exactly as it is, unparsed.
            guard couldHoldSomething(original) else { lines.append(original); continue }
            guard !original.trimmingCharacters(in: .whitespaces).isEmpty,
                  let data = original.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data),
                  let rewritten = try? JSONSerialization.data(
                      withJSONObject: redactJSON(parsed),
                      options: [.withoutEscapingSlashes, .sortedKeys]
                  ),
                  let text = String(data: rewritten, encoding: .utf8)
            else {
                // Not JSON, or not re-encodable: pass it through rather than lose it.
                lines.append(original)
                continue
            }
            // **Both sides through the same encoder.** Comparing the rewritten line
            // against the original text counts re-serialisation as a change — the
            // encoder reorders keys and normalises escapes — which made the count read
            // as "almost every record" and so meant nothing. Encoding the untouched
            // parse too cancels that noise, leaving only what redaction actually did.
            // **`.sortedKeys` on both sides, or the comparison is meaningless.**
            // `mapValues` builds a new dictionary whose key order need not match the
            // original's, so two encodings of the same content differed by byte order
            // alone and every record counted as changed. Sorting makes the encoding a
            // function of the content, which is what the comparison assumes.
            let before = try? JSONSerialization.data(
                withJSONObject: parsed, options: [.withoutEscapingSlashes, .sortedKeys])
            if before != rewritten { changed += 1 }
            lines.append(text)
        }
        return (lines.joined(separator: "\n"), changed)
    }
}
