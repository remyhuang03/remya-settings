#!/usr/bin/env python3
"""Regenerate AI provider brand icons and manifest.json for remya_settings_client.

Downloads a pinned @lobehub/icons-static-svg (MIT) tarball, verifies its npm
integrity hash and copies one SVG per CodexBar provider id. The tarball is
untrusted data: nothing from it is executed and extraction uses filter="data".
"""

import base64
import hashlib
import io
import json
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

LOBE_VERSION = "1.102.0"
LOBE_URL = (
    "https://registry.npmjs.org/@lobehub/icons-static-svg/-/"
    f"icons-static-svg-{LOBE_VERSION}.tgz"
)
LOBE_INTEGRITY = (
    "sha512-3Na6S2kdslmsfnBjuL0PQWQClrmuWe/pWThRN/3J2VzPg5MhVghy8knVu7kd1/"
    "lqA9ydZBvwmnKLzuBo0Wm6Qw=="
)
MODELS_DEV_URL = "https://models.dev/api.json"

OUT = Path(__file__).resolve().parent.parent / (
    "packages/remya_settings_client/assets/ai_providers"
)

# CodexBar id -> lobe icon slug; None skips an icon whose lobe namesake is a
# different product.
LOBE_ALIASES = {
    "azureopenai": "azure",
    "claudeplatform": "claude",
    "clinepass": "cline",
    "opencodego": "opencode",
    "alibabatokenplan": "alibaba",
    "qwencloud": "qwen",
    "copilot": "githubcopilot",
    "kilo": "kilocode",
    "mimo": "xiaomimimo",
    "ibmbob": "ibm",
    "nous": "nousresearch",
    "typesafe": "typesafeai",
    "siliconflow": "siliconcloud",
    "traecn": "trae",
    "pi": None,
    "muse": None,
}

# CodexBar id -> models.dev provider id; ids missing here use the same id
# when models.dev has it.
MODELS_DEV_ALIASES = {
    "claude": "anthropic",
    "claudeplatform": "anthropic",
    "codex": "openai",
    "gemini": "google",
    "vertexai": "google-vertex",
    "bedrock": "amazon-bedrock",
    "azureopenai": "azure",
    "grok": "xai",
    "moonshot": "moonshotai",
    "kimi": "kimi-code-plan-global",
    "copilot": "github-copilot",
    "fireworks": "fireworks-ai",
    "clinepass": "cline-pass",
    "opencodego": "opencode-go",
    "alibabatokenplan": "alibaba-token-plan",
    "mimo": "xiaomi",
    "abliteration": "abliteration-ai",
}

FILL = re.compile(r'fill="#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})"')
STOP = re.compile(r'stop-color="#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})"')


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "sync_ai_icons"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def provider_ids() -> list[str]:
    try:
        output = subprocess.run(
            ["codexbar", "config", "providers", "--format", "json"],
            capture_output=True, check=True, text=True, timeout=60,
        ).stdout
        return [row["provider"] for row in json.loads(output)]
    except (OSError, subprocess.SubprocessError, ValueError, KeyError) as error:
        manifest = OUT / "manifest.json"
        if not manifest.exists():
            sys.exit(f"codexbar unavailable ({error}) and no manifest to reuse")
        print(f"codexbar unavailable ({error}); reusing manifest ids")
        return list(json.loads(manifest.read_text()))


def brand_color(svg: str) -> str | None:
    """First solid hex fill, else gradient stop, that is not near-gray."""
    for match in [*FILL.finditer(svg), *STOP.finditer(svg)]:
        value = match.group(1)
        if len(value) == 3:
            value = "".join(c * 2 for c in value)
        r, g, b = (int(value[i:i + 2], 16) for i in (0, 2, 4))
        if max(r, g, b) - min(r, g, b) > 24:
            return f"#{value.upper()}"
    return None


def main() -> None:
    ids = provider_ids()
    tarball = fetch(LOBE_URL)
    algorithm, expected = LOBE_INTEGRITY.split("-", 1)
    actual = base64.b64encode(hashlib.new(algorithm, tarball).digest()).decode()
    if actual != expected:
        sys.exit("lobe-icons tarball integrity mismatch")
    models_dev = json.loads(fetch(MODELS_DEV_URL))

    with tempfile.TemporaryDirectory() as temp:
        with tarfile.open(fileobj=io.BytesIO(tarball), mode="r:gz") as archive:
            archive.extractall(temp, filter="data")
        icons = Path(temp) / "package" / "icons"
        if OUT.exists():
            shutil.rmtree(OUT)
        OUT.mkdir(parents=True)
        manifest, color, mono, none = {}, [], [], []
        for id in ids:
            slug = LOBE_ALIASES.get(id, id)
            source = None
            if slug is not None:
                for name in (f"{slug}-color.svg", f"{slug}.svg"):
                    if (icons / name).is_file():
                        source = icons / name
                        break
            if source is None:
                none.append(id)
                continue
            svg = source.read_text(encoding="utf-8")
            if "<style" in svg or "<script" in svg or "class=" in svg:
                none.append(id)
                continue
            (OUT / f"{id}.svg").write_text(svg, encoding="utf-8")
            (color if source.name.endswith("-color.svg") else mono).append(id)
            models = MODELS_DEV_ALIASES.get(id, id)
            manifest[id] = {
                "icon": f"{id}.svg",
                "color": brand_color(svg),
                "modelsDev": models if models in models_dev else None,
            }
    (OUT / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    size = sum(path.stat().st_size for path in OUT.iterdir())
    print(f"lobe-icons {LOBE_VERSION}: {len(ids)} providers, {size} bytes")
    print(f"color ({len(color)}): {' '.join(color)}")
    print(f"mono ({len(mono)}): {' '.join(mono)}")
    print(f"none ({len(none)}): {' '.join(none)}")


if __name__ == "__main__":
    main()
