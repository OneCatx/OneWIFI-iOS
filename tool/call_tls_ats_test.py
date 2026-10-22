"""Compare app ATS policies using an identical, unauthenticated pinned TLS probe."""
import copy
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
from urllib.parse import urlsplit

origin = os.environ["PROBE_ORIGIN"]
pin = os.environ["PROBE_PIN"]
host = urlsplit(origin).hostname
assert urlsplit(origin).scheme == "https" and host
assert len(pin) == 64 and all(c in "0123456789abcdef" for c in pin)
source = Path(os.environ["RUNNER_TEMP"], "main.swift")
app = plistlib.loads(Path("ios/Runner/Info.plist").read_bytes())
scoped = app["NSAppTransportSecurity"]
assert not scoped.get("NSAllowsArbitraryLoads", False)
assert scoped.get("NSExceptionDomains") == {
    "8.137.155.86": {"NSExceptionAllowsInsecureHTTPLoads": True},
}
assert host in scoped["NSExceptionDomains"], "Probe must target the configured gateway exception"
baseline = copy.deepcopy(scoped)
baseline.pop("NSExceptionDomains")
# ATS also permits HTTP for the exception host; the native configuration rejects
# public HTTP. HTTPS pin, hostname, validity and SecTrust checks remain mandatory.
results = {}
with tempfile.TemporaryDirectory(prefix="call-ats-") as directory:
    root = Path(directory)
    for name, ats in [("without-exception", baseline), ("app-policy", scoped)]:
        info = root / f"{name}.plist"
        info.write_bytes(plistlib.dumps({
            "CFBundleIdentifier": f"net.onewifi.tlsprobe.{name}",
            "CFBundleName": "CallTLSProbe",
            "CFBundleVersion": "1",
            "NSAppTransportSecurity": ats,
        }))
        binary = root / name
        subprocess.run([
            "swiftc", "-swift-version", "5", str(source),
            "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
            "-Xlinker", "__info_plist", "-Xlinker", str(info),
            "-o", str(binary),
        ], check=True)
        print(f"=== {name} ===", flush=True)
        result = subprocess.run([str(binary), origin, pin], timeout=35)
        results[name] = result.returncode
        if name == "app-policy":
            wrong_pin = ("0" if pin[0] != "0" else "1") + pin[1:]
            rejected = subprocess.run([str(binary), origin, wrong_pin], timeout=35,
                                      capture_output=True, text=True)
            print("=== app-policy wrong pin ===", flush=True)
            print(rejected.stdout, flush=True)
            assert rejected.returncode != 0 and "pinMatches=false" in rejected.stdout
            assert "httpStatus=" not in rejected.stdout
    print(f"ATS comparison exit codes: {results}", flush=True)
    assert results["without-exception"] != 0, results
    assert results["app-policy"] == 0, results