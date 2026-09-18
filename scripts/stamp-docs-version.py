#!/usr/bin/env python3
"""Keep docs/index.html's version in step with project.yml.

The landing page is static, so the version is written into it rather than read
at runtime. That's fine as long as nothing can forget to update it — hence this,
wired into `make dmg`, so cutting a release can't ship a page that disagrees
with the app.
"""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
project = root / "project.yml"
page = root / "docs" / "index.html"

match = re.search(r'MARKETING_VERSION:\s*"?([0-9][0-9.]*)"?', project.read_text())
if not match:
    sys.exit("could not find MARKETING_VERSION in project.yml")
version = match.group(1)

html = page.read_text()
before = html

# The line under the download buttons.
html = re.sub(r"<b>Version [0-9][0-9.]*</b>", f"<b>Version {version}</b>", html)
# The row in the install table.
html = re.sub(
    r"(<td>Version</td><td>)[0-9][0-9.]*(</td>)",
    lambda m: m.group(1) + version + m.group(2),
    html,
)
# The asset filename in the download link.
html = re.sub(r"DynamicNotch-[0-9][0-9.]*\.dmg", f"DynamicNotch-{version}.dmg", html)

if html != before:
    page.write_text(html)
    print(f"docs: stamped version {version}")
else:
    print(f"docs: already at version {version}")
