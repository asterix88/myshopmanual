#!/usr/bin/env python3
"""Upload a built dist/ folder to the Cloudflare R2 bucket the app reads from.

Only files whose content changed are uploaded (compared by sha256), and
catalog.json goes last so the app never sees a catalog pointing at files
that are not there yet.

Needs these environment variables (from Cloudflare dashboard, R2 >
Manage API tokens; never commit them):

    R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET

    python tools/upload_r2.py dist             # upload changes
    python tools/upload_r2.py dist --dry-run   # only list what would change
    python tools/upload_r2.py dist --prune     # also delete files no longer in the catalog
    python tools/upload_r2.py dist --warm-all  # only warm every PDF (no upload, no keys)

After uploading, every new or changed PDF is asked for once through the
public address (R2_PUBLIC_URL, default https://mymanual.my.id). Cloudflare
copies the whole file from R2 into its nearby server on the first request,
which for a big Shop Manual takes several seconds; doing it here means the
first mechanic to open it does not wait for that.
"""

import argparse
import json
import os
import sys
import time
import urllib.request
from pathlib import Path

CATALOG = "catalog.json"


def catalog_paths(catalog: dict) -> dict[str, str]:
    """Every object the catalog references, mapped to its sha256."""
    paths = {}
    for unit in catalog["units"]:
        for f in unit["files"]:
            for part in ("pdf", "index"):
                paths[f[part]["path"]] = f[part]["sha256"]
        if "spec" in unit:
            paths[unit["spec"]["path"]] = unit["spec"]["sha256"]
    return paths


def warm(keys: list[str]) -> None:
    """Asks Cloudflare for the last 1 KB of each PDF in [keys], which makes
    it copy the whole file into its cache (see the note at the top)."""
    base = os.environ.get("R2_PUBLIC_URL", "https://mymanual.my.id").rstrip("/")
    pdfs = [k for k in keys if k.endswith(".pdf")]
    if pdfs:
        print(f"=== Memanaskan {len(pdfs)} PDF di server Cloudflare ===")
    for key in pdfs:
        request = urllib.request.Request(
            f"{base}/{urllib.request.quote(key)}",
            headers={"Range": "bytes=-1024", "User-Agent": "MyManual-update"},
        )
        start = time.monotonic()
        try:
            with urllib.request.urlopen(request, timeout=300) as response:
                response.read()
            print(f"siap    {key}  ({time.monotonic() - start:.1f} s)")
        except Exception as e:  # warming is only a speed-up; never fail the update
            print(f"lewati  {key}  ({e})")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("dist", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--prune", action="store_true")
    parser.add_argument("--warm-all", action="store_true")
    args = parser.parse_args()

    catalog = json.loads((args.dist / CATALOG).read_text())
    wanted = catalog_paths(catalog)

    if args.warm_all:
        warm(sorted(wanted))
        return 0

    missing = [k for k in ("R2_ACCOUNT_ID", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "R2_BUCKET")
               if not os.environ.get(k)]
    if missing:
        print("missing environment variables: " + ", ".join(missing), file=sys.stderr)
        return 1

    import boto3  # imported here so --help works without it installed

    s3 = boto3.client(
        "s3",
        endpoint_url=f"https://{os.environ['R2_ACCOUNT_ID']}.r2.cloudflarestorage.com",
        aws_access_key_id=os.environ["R2_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["R2_SECRET_ACCESS_KEY"],
        region_name="auto",
    )
    bucket = os.environ["R2_BUCKET"]

    remote = {}
    for page in s3.get_paginator("list_objects_v2").paginate(Bucket=bucket):
        for obj in page.get("Contents", []):
            remote[obj["Key"]] = obj

    def remote_sha(key: str) -> str | None:
        if key not in remote:
            return None
        head = s3.head_object(Bucket=bucket, Key=key)
        return head.get("Metadata", {}).get("sha256")

    to_upload = [key for key, sha in sorted(wanted.items()) if remote_sha(key) != sha]
    to_delete = sorted(k for k in remote if k not in wanted and k != CATALOG) if args.prune else []

    for key in to_upload:
        size = (args.dist / key).stat().st_size
        print(f"upload  {key}  ({size / 1e6:.1f} MB)")
        if not args.dry_run:
            content_type = "application/pdf" if key.endswith(".pdf") else "application/octet-stream"
            s3.upload_file(
                str(args.dist / key), bucket, key,
                ExtraArgs={"ContentType": content_type, "Metadata": {"sha256": wanted[key]}},
            )

    print(f"upload  {CATALOG}")
    if not args.dry_run:
        s3.upload_file(
            str(args.dist / CATALOG), bucket, CATALOG,
            ExtraArgs={"ContentType": "application/json", "CacheControl": "no-cache"},
        )

    for key in to_delete:
        print(f"delete  {key}")
        if not args.dry_run:
            s3.delete_object(Bucket=bucket, Key=key)

    print(f"{len(to_upload)} file(s) uploaded, {len(to_delete)} deleted"
          + (" (dry run)" if args.dry_run else ""))
    if not args.dry_run:
        warm(to_upload)
    return 0


if __name__ == "__main__":
    sys.exit(main())
