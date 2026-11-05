"""Network-enabled official-artifact preparation. Never invoked by offline gates."""
import hashlib
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path
from metadata import verify, relative

root = Path(__file__).resolve().parents[1]
items = verify(root)
out = root / "build/artifacts"
out.mkdir(parents=True, exist_ok=True)
os.chmod(root / "build", 0o777)
allowed = {"github.com", "raw.githubusercontent.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com",
           "deb.debian.org", "security.debian.org", "opam.ocaml.org"}


class OfficialRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        url = urllib.parse.urlparse(newurl)
        if url.scheme != "https" or url.hostname not in allowed:
            raise ValueError("unapproved redirect")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


opener = urllib.request.build_opener(OfficialRedirect())
checksums = []
for item in items:
    url = urllib.parse.urlparse(item["url"])
    if url.scheme != "https" or url.hostname not in allowed or url.username or url.password:
        raise ValueError("nonofficial artifact URL")
    path = out / relative(item["path"])
    path.parent.mkdir(parents=True, exist_ok=True)
    h = hashlib.sha256()
    total = 0
    temporary = path.with_name(path.name + ".partial")
    with opener.open(item["url"], timeout=60) as response, temporary.open("wb") as target:
        while True:
            block = response.read(65536)
            if not block:
                break
            total += len(block)
            if total > 268435456:
                raise ValueError("artifact byte bound")
            h.update(block)
            target.write(block)
    if h.hexdigest() != item["sha256"]:
        raise ValueError("official artifact checksum mismatch")
    temporary.replace(path)
    checksums.append(item["sha256"] + "  " + item["path"] + "\n")
(out / "SHA256SUMS").write_text("".join(sorted(checksums)))
verify(root, out)
print("Verified official preparation artifacts; no dependency resolution performed.")
sys.exit(0)
