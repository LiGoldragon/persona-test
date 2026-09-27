"""The oracle outside Flow for persona-test's message-flow scenario.

It reads what Flow answered, as datom text, and what the seat itself wrote
to disk, and judges the second without asking Flow. Nothing here imports or
calls Flow: the footer, the first-prompt shapes and the skill expansion form
are written below from Flow 0.17.4's source and Claude Code's transcript
shape, as the specification the run witnesses, and every hash is computed
here.

    oracle.py reply FILE...            Flow's answers: verdict, ids, hash
    oracle.py lifecycle FILE FLOW_ID   a flow's lifecycle in a List answer
    oracle.py processes PID            descendants of PID, with their argv
    oracle.py alive PID...             which of PID... still exist
    oracle.py transcript SPEC_JSON     the transcript checks for one start
"""

import hashlib
import json
import os
import re
import sys

FOOTER = (
    " When every skill has loaded, reply once with exactly "
    "FLOW_LAUNCH_RECEIPT_V2 and nothing else."
)
RECEIPT = "FLOW_LAUNCH_RECEIPT_V2"
HEX64 = re.compile(r"^[0-9a-f]{64}$")


class Datom:
    """Reads datom text into nested Python values: a struct or a vector is a
    list, a variant carrying a value is a (name, value) tuple, and a bare run
    or a guillemet string is a str."""

    def __init__(self, text):
        self.text = text
        self.at = 0

    def skip(self):
        while self.at < len(self.text) and self.text[self.at].isspace():
            self.at += 1

    def value(self):
        self.skip()
        glyph = self.text[self.at]
        if glyph in "{[":
            closing = "}" if glyph == "{" else "]"
            self.at += 1
            items = []
            while True:
                self.skip()
                if self.text[self.at] == closing:
                    self.at += 1
                    return items
                items.append(self.value())
        if glyph == "«":
            self.at += 1
            out = []
            while self.text[self.at] != "»":
                if self.text[self.at] == "\\" and self.text[self.at + 1] in "»\\":
                    self.at += 1
                out.append(self.text[self.at])
                self.at += 1
            self.at += 1
            return "".join(out)
        start = self.at
        while (
            self.at < len(self.text)
            and not self.text[self.at].isspace()
            and self.text[self.at] not in "{}[]«»"
        ):
            self.at += 1
        run = self.text[start:self.at]
        if run.endswith(".") and self.at < len(self.text) and self.text[self.at] in "{[«":
            return (run[:-1], self.value())
        return run

    @classmethod
    def frames(cls, text):
        reader = cls(text)
        values = []
        while True:
            reader.skip()
            if reader.at >= len(text):
                return values
            values.append(reader.value())


class Reply:
    """What one or more Flow answers say about one launch."""

    @staticmethod
    def head(value):
        if isinstance(value, tuple):
            return value[0]
        return value.split(".")[0] if "." in value else value

    @staticmethod
    def binding(option):
        if isinstance(option, tuple) and option[0] == "Some" and isinstance(option[1], list):
            return option[1]
        return None

    @classmethod
    def read(cls, texts):
        found = dict(verdict=None, prompt_sha256=None, flow_id=None, session_id=None, pane_id=None, phases=[])
        for text in texts:
            for frame in Datom.frames(text):
                head = cls.head(frame)
                if isinstance(frame, str) and frame.startswith("StartRejected."):
                    found["verdict"] = frame
                elif head == "Started":
                    found["verdict"] = "Started"
                    found["flow_id"], found["session_id"] = frame[1][0], frame[1][1]
                elif head == "StartAmbiguous":
                    intent = frame[1]
                    found["verdict"] = "StartAmbiguous"
                    found["prompt_sha256"] = found["prompt_sha256"] or intent[1]
                    found["flow_id"], found["session_id"] = intent[2], intent[3]
                    found["pane_id"] = intent[8][4]
                elif head == "LaunchPending":
                    attempt = frame[1]
                    found["verdict"] = "LaunchPending." + str(attempt[4])
                    if str(attempt[4]) not in found["phases"]:
                        found["phases"].append(str(attempt[4]))
                    if HEX64.match(attempt[2]):
                        found["prompt_sha256"] = found["prompt_sha256"] or attempt[2]
                    bound = cls.binding(attempt[6])
                    if bound:
                        found["flow_id"], found["session_id"] = bound[1], bound[2]
                        found["pane_id"] = bound[4][4]
        return found


class Lifecycle:
    @staticmethod
    def of(text, flow_id):
        for frame in Datom.frames(text):
            if isinstance(frame, tuple) and frame[0] == "Listed":
                for node in frame[1]:
                    if node and node[0] == flow_id:
                        return node[-1]
        return "absent"


class Processes:
    @staticmethod
    def parent(pid):
        try:
            with open("/proc/%s/stat" % pid) as handle:
                stat = handle.read()
        except OSError:
            return None
        return int(stat[stat.rindex(")") + 2:].split()[1])

    @classmethod
    def descendants(cls, root):
        children = {}
        for entry in os.listdir("/proc"):
            if entry.isdigit():
                parent = cls.parent(entry)
                if parent is not None:
                    children.setdefault(parent, []).append(int(entry))
        found, stack = [], [int(root)]
        while stack:
            for child in children.get(stack.pop(), []):
                found.append(child)
                stack.append(child)
        out = []
        for pid in sorted(found):
            try:
                with open("/proc/%d/cmdline" % pid, "rb") as handle:
                    argv = [part.decode("utf-8", "replace") for part in handle.read().split(b"\0") if part]
            except OSError:
                continue
            out.append(dict(pid=pid, argv=argv))
        return out


class Transcript:
    """The checks for one start, in the order Flow meets the same facts."""

    def __init__(self, spec):
        self.spec = spec
        self.checks = []

    def check(self, name, passed, detail, live_only=False):
        """A live-only check is one a stand-in seat can only answer by its
        own fixture rule: under the stand-in it is marked, not witnessed."""
        record = dict(name=name, passed=bool(passed), detail=detail)
        if live_only and self.spec.get("seat") == "stand-in":
            record["live_only"] = True
            record["detail"] = detail + " [stand-in: this tests the fixture's own rule; witnessed only by a live run]"
        self.checks.append(record)
        return passed

    @staticmethod
    def expansion(path):
        if not os.path.isfile(path):
            return None
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        if source.startswith("---\n"):
            closing = source.index("\n---\n", 4)
            source = source[closing + len("\n---\n"):].lstrip("\n")
        return "Base directory for this skill: %s\n\n%s" % (os.path.dirname(os.path.realpath(path)), source)

    def files(self):
        name = self.spec["session_id"] + ".jsonl"
        found = []
        for directory, _, files in os.walk(self.spec["projects"]):
            if name in files:
                found.append(os.path.join(directory, name))
        return found

    @staticmethod
    def command(text):
        match = re.match(
            r"^<command-message>([^<]*)</command-message>\n<command-name>/([^<]*)</command-name>"
            r"(?:\n<command-args>(.*)</command-args>)?$",
            text,
            re.S,
        )
        if match and match.group(1) == match.group(2):
            return match.group(2), match.group(3) or ""
        return None

    def typed_entries(self, rows):
        entries = []
        for row in rows:
            content = row.get("message", {}).get("content")
            if row.get("type") != "user" or row.get("isMeta") or not isinstance(content, str):
                continue
            record = self.command(content)
            if record and record[0] not in self.spec["skills"]:
                continue
            if content.startswith("<local-command-"):
                continue
            entries.append(content)
        return entries

    def first_turn(self, entries):
        """The text typed as the first turn, and whether it came wrapped."""
        names, argument = [], None
        for entry in entries:
            record = self.command(entry)
            if not record:
                break
            names.append(record[0])
            argument = record[1]
        if names:
            return "/" + " /".join(names) + (" " + argument if argument else ""), False, len(names)
        entry = entries[0]
        wrapped = re.match(r"^<pasted_content(?:\s[^<>\r\n]*)?>\n(.*)\n</pasted_content>$", entry, re.S)
        if wrapped:
            return wrapped.group(1), True, 1
        return entry, False, 1

    def expected_text(self, bundle):
        spec = self.spec
        if spec["form"] == "stacked":
            head = " ".join("/" + name for name in spec["skills"])
            return "%s Read %s for your launch mode, then: %s%s" % (head, bundle, spec["instruction"], FOOTER)
        return (
            "Read %s for your launch mode, then load these skills through the Skill tool in this order: %s. Then: %s%s"
            % (bundle, ", ".join(spec["skills"]), spec["instruction"], FOOTER)
        )

    def judge(self):
        spec = self.spec
        unavailable = spec.get("unavailable_skill")
        if unavailable:
            present = [
                os.path.join(catalog, name, "SKILL.md")
                for name in spec["skills"]
                for catalog in spec["catalogs"]
                if os.path.isfile(os.path.join(catalog, name, "SKILL.md"))
            ]
            found = [path for path in present if os.path.basename(os.path.dirname(path)) == unavailable]
            others = {os.path.basename(os.path.dirname(path)) for path in present} - {unavailable}
            wanted = set(spec["skills"]) - {unavailable}
            if not self.check(
                "skill-unavailable",
                not found and others == wanted,
                "%s is in no catalog Flow reads (%s); the other selected skills are present"
                % (unavailable, ", ".join(spec["catalogs"])),
            ):
                return
        files = self.files()
        if not self.check("transcript-located", len(files) == 1, "%d file(s) named %s.jsonl" % (len(files), spec["session_id"])):
            return
        rows = []
        with open(files[0], "rb") as handle:
            for line in handle:
                try:
                    row = json.loads(line)
                except ValueError:
                    continue
                if row.get("sessionId", row.get("session_id")) == spec["session_id"]:
                    rows.append(row)
        entries = self.typed_entries(rows)
        if not self.check("first-entry-present", entries, "%d typed user entr(ies)" % len(entries)):
            return
        typed, wrapped, consumed = self.first_turn(entries)
        self.check(
            "route",
            wrapped == spec["wrapped"],
            "first turn %s, expected %s" % ("wrapped" if wrapped else "plain", "wrapped" if spec["wrapped"] else "plain"),
            live_only=True,
        )
        if not self.check("footer-present", typed.endswith(FOOTER), "first turn ends with Flow's receipt footer"):
            return
        body = typed[: -len(FOOTER)]
        digest = hashlib.sha256(body.encode("utf-8")).hexdigest()
        if not self.check(
            "prompt-hash",
            digest == spec["stored_sha256"],
            "sha256 of the text less the footer %s, Flow stored %s" % (digest, spec["stored_sha256"]),
        ):
            return
        bundle = re.search(r"Read (/\S+) for your launch mode", typed)
        bundle_path = bundle.group(1) if bundle else ""
        self.check(
            "bundle-copy",
            bundle_path.startswith(spec["bundle_directory"] + "/"),
            "first turn names %s under %s" % (bundle_path or "no bundle", spec["bundle_directory"]),
        )
        self.check(
            "first-entry-bytes",
            typed == self.expected_text(bundle_path),
            "first turn equals the expected text byte for byte (%d bytes)" % len(typed.encode("utf-8")),
        )
        first_line = spec["instruction"].split("\n")[0]
        carrying = [entry for entry in entries[consumed:] if first_line in entry]
        self.check(
            "one-entry",
            not carrying and (("\n" in spec["instruction"]) == ("\n" in typed)),
            "no later entry repeats the instruction; line break %s" % ("kept" if "\n" in typed else "absent"),
        )
        companions = [row for row in rows if row.get("type") == "user" and row.get("isMeta") and row.get("turnCompanion")]
        texts = []
        for row in companions:
            content = row.get("message", {}).get("content")
            if isinstance(content, list) and len(content) == 1:
                texts.append(content[0].get("text", ""))
        expected = [self.expansion(path) for path in spec["skill_paths"]]
        order = []
        for text in texts:
            for index, expansion in enumerate(expected):
                if expansion is None:
                    continue
                if text == expansion or text.startswith(expansion.rstrip()):
                    order.append(spec["skills"][index])
                    break
        self.check(
            "skill-expansions",
            order[: len(expected)] == spec["skills"],
            "expanded in order %s, selected %s" % (order, spec["skills"]),
        )
        receipts = [
            row for row in rows
            if row.get("type") == "assistant"
            and [part.get("text") for part in row.get("message", {}).get("content", []) if isinstance(part, dict)] == [RECEIPT]
        ]
        self.check("receipt", len(receipts) == 1, "%d receipt row(s)" % len(receipts))
        models = sorted({row["message"].get("model") for row in rows if row.get("type") == "assistant" and row.get("message", {}).get("model") not in (None, "<synthetic>")})
        self.check("model", models == [spec["model"]], "assistant rows ran as %s, intended %s" % (models, spec["model"]))
        efforts = sorted({row.get(key) for row in rows if row.get("type") == "assistant" for key in ("effort", "perTurnEffort") if row.get(key) is not None})
        self.check(
            "effort",
            efforts in ([], [spec["effort"]]),
            "assistant rows record effort %s, intended %s%s" % (efforts, spec["effort"], " (the harness records none for this model)" if not efforts else ""),
        )
        argv = spec.get("seat_argv") or []
        flags = dict(zip(argv, argv[1:]))
        self.check(
            "launch-flags",
            flags.get("--model") == spec["model"] and flags.get("--effort") == spec["effort"],
            "seat process started with --model %s --effort %s" % (flags.get("--model"), flags.get("--effort")),
        )

    def result(self):
        self.judge()
        failed = [check["name"] for check in self.checks if not check["passed"]]
        return dict(checks=self.checks, passed=not failed, first_failed=failed[0] if failed else None)


def main(argv):
    command = argv[1]
    if command == "reply":
        texts = []
        for path in argv[2:]:
            with open(path, encoding="utf-8") as handle:
                texts.append(handle.read())
        print(json.dumps(Reply.read(texts)))
    elif command == "lifecycle":
        with open(argv[2], encoding="utf-8") as handle:
            print(Lifecycle.of(handle.read(), argv[3]))
    elif command == "processes":
        print(json.dumps(Processes.descendants(argv[2])))
    elif command == "alive":
        print(json.dumps([pid for pid in argv[2:] if os.path.exists("/proc/%s" % pid)]))
    elif command == "transcript":
        with open(argv[2], encoding="utf-8") as handle:
            print(json.dumps(Transcript(json.load(handle)).result()))
    else:
        sys.exit("unknown oracle command: %s" % command)


if __name__ == "__main__":
    main(sys.argv)
