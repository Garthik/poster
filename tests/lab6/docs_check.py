#!/usr/bin/env python3
"""Static standalone-guide QA. Does not claim a browser/clipboard UI test."""
from html.parser import HTMLParser
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


class Guide(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids = []
        self.anchors = []
        self.step_anchors = []
        self.steps = []
        self.checkboxes = []
        self.buttons = 0
        self.blocks = 0
        self.scripts = []
        self.in_script = False

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        classes = set(attrs.get("class", "").split())
        if "id" in attrs:
            self.ids.append(attrs["id"])
        if tag == "a" and attrs.get("href", "").startswith("#"):
            self.anchors.append(attrs["href"][1:])
            if "navitem" in classes:
                self.step_anchors.append(attrs["href"][1:])
        if tag == "section" and "data-step" in attrs:
            self.steps.append(attrs["id"])
        if tag == "input" and "stepcheckbox" in classes:
            assert attrs.get("type") == "checkbox"
            self.checkboxes.append(attrs["data-key"])
        if tag == "button" and "copy" in classes:
            self.buttons += 1
        if tag == "div" and "code-block" in classes:
            self.blocks += 1
        if tag == "script":
            assert "src" not in attrs, "No external JS in standalone guide"
            self.in_script = True
        if tag == "link":
            assert attrs.get("rel") != "stylesheet", "No external CSS"
        if tag in ("img", "iframe"):
            assert not attrs.get("src", "").startswith(("http:", "https:")), "No external visual dependencies"

    def handle_endtag(self, tag):
        if tag == "script":
            self.in_script = False

    def handle_data(self, data):
        if self.in_script:
            self.scripts.append(data)


guide = Guide()
source = (ROOT / "ticket-platform-lab6-demonstration-guide.html").read_text(encoding="utf8")
assert source == (ROOT / "demonstration-guide-lab6.html").read_text(encoding="utf8"), "Documented filename stays synchronized"
guide.feed(source)
assert len(guide.ids) == len(set(guide.ids)), "Unique anchors"
assert all(a in guide.ids for a in guide.anchors)
assert guide.step_anchors == guide.steps == guide.checkboxes == [f"step-{i}" for i in range(1, 17)], "Every step has navigation and an independent progress checkbox"
assert guide.buttons == guide.blocks and guide.blocks > 0, "Every command block has a copy button"
assert len(guide.scripts) == 1
assert "navigator.clipboard.writeText" in guide.scripts[0]
assert "document.execCommand('copy')" in guide.scripts[0], "file:// clipboard fallback"
assert "ticket_lab6_guide_checked_v2" in guide.scripts[0] and "localStorage.setItem" in guide.scripts[0]
assert "window.print()" in guide.scripts[0]
assert not re.search(r"https?://[^<]*\.(?:js|css)[\"']", source)
out = ROOT / "artifacts/lab6/logs/guide-script.js"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(guide.scripts[0], encoding="utf8")
print(f"PASS static HTML: {len(guide.steps)} steps/navigation/checkboxes, {guide.blocks} copy blocks, synchronized filenames, no external assets")
print("Inline JS extracted for node --check; browser rendering and actual clipboard are separate checks")
