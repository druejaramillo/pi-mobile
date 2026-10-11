#!/usr/bin/env python3
"""Export an explicitly selected VoxType TOML into Pi Mobile's offline profile.

Python 3.11+; no shell commands, environment files, or sibling configuration reads.
"""

import argparse
import json
import re
import sys
from pathlib import Path

import tomllib

OUTPUT = (
    Path(__file__).resolve().parents[1] / "ios/PiMobile/Resources/voxtype-profile.json"
)
SPOKEN_ALIAS = re.compile(r"[a-z0-9]+(?:[ -][a-z0-9]+)*", re.ASCII)
SLASH_COMMAND = re.compile(r"/(?:skill:)?[a-z0-9]+(?:-[a-z0-9]+)*", re.ASCII)


def boolean_setting(section: dict, key: str, default: bool) -> bool:
    """Read only a whitelisted boolean, rejecting misleading TOML types."""
    value = section.get(key, default)
    if type(value) is not bool:
        raise ValueError(f"VoxType import: {key} must be a boolean")
    return value


def sanitized_profile(config: dict) -> dict:
    """Keep only the v3 audio contract and deterministic offline text settings."""
    audio = config.get("audio", {})
    parakeet = config.get("parakeet", {})
    text = config.get("text", {})
    output = config.get("output", {})
    if (
        config.get("engine") != "parakeet"
        or parakeet.get("model") != "parakeet-tdt-0.6b-v3"
    ):
        raise ValueError("VoxType import: only Parakeet TDT 0.6b v3 is supported")
    for key, required in (("sample_rate", 16000), ("max_duration_secs", 300)):
        value = audio.get(key, required)
        if type(value) is not int or value != required:
            raise ValueError(f"VoxType import: {key} must be {required}")
    append_text = output.get("append_text", " ")
    if append_text not in ("", " "):
        raise ValueError("VoxType import: append_text must be empty or one space")

    # Slash-valued commands only. Excludes format directives, paths, desktop
    # prefix-repair passes, and any arbitrary values that might contain secrets.
    aliases = {}
    for spoken, command in text.get("replacements", {}).items():
        normalized = " ".join(spoken.lower().split())
        if (
            SPOKEN_ALIAS.fullmatch(normalized)
            and isinstance(command, str)
            and SLASH_COMMAND.fullmatch(command)
        ):
            if normalized in aliases and aliases[normalized] != command:
                raise ValueError(
                    "VoxType import: conflicting case-insensitive command aliases"
                )
            aliases[normalized] = command
    replacements = [
        {"spoken": spoken, "command": command}
        for spoken, command in sorted(
            aliases.items(), key=lambda item: (-len(item[0]), item[0], item[1])
        )
    ]
    return {
        "schemaVersion": 1,
        "engine": "parakeet",
        "model": "parakeet-tdt-0.6b-v3",
        "sampleRate": 16000,
        "maxDurationSeconds": 300,
        "feedbackEnabled": boolean_setting(audio.get("feedback", {}), "enabled", True),
        "spokenPunctuation": boolean_setting(text, "spoken_punctuation", False),
        "filterFillerWords": boolean_setting(text, "filter_filler_words", False),
        "appendSpace": append_text == " ",
        "replacements": replacements,
    }


def main() -> int:
    """Read only the explicit TOML path and write the fixed owned resource path."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "config",
        type=Path,
        help="Explicit VoxType config.toml path (no automatic discovery)",
    )
    args = parser.parse_args()
    try:
        config_path = args.config.resolve(strict=True)
        if config_path.suffix.lower() != ".toml":
            raise ValueError("VoxType import: the explicit input must be a TOML file")
        with config_path.open("rb") as source:
            profile = sanitized_profile(tomllib.load(source))
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(
            json.dumps(profile, indent=2, ensure_ascii=True) + "\n", encoding="utf-8"
        )
    except (OSError, ValueError, TypeError, AttributeError):
        # Do not echo TOML/parser input or arbitrary configuration values.
        print(
            "VoxType import failed: check the explicit TOML path and supported profile settings.",
            file=sys.stderr,
        )
        return 1
    print(f"Wrote {OUTPUT} ({len(profile['replacements'])} offline command aliases)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
