#!/usr/bin/env python3
"""Initialize private instance settings and export a shell connection environment.

Requires Python 3 and Docker Compose; has no machine/VM-specific paths.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import shlex
import subprocess
import tempfile
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]


def write_private(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as handle:
        temporary = Path(handle.name)
        try:
            handle.write(content)
            handle.close()
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


def initialize(env_file, data_dir):
    """Exclusive creation: never replace a password or settings on rerun."""
    env_file.parent.mkdir(parents=True, exist_ok=True)
    # Compose single-quoted values are literal (including dollar signs).
    directory = str(data_dir).replace("'", "\\'")
    content = (
        "POSTGRES_USER=dev\n"
        f"POSTGRES_PASSWORD={secrets.token_hex(32)}\n"
        "POSTGRES_DB=postgres\n"
        f"POSTGRES_DATA_DIR='{directory}'\n"
        "POSTGRES_BIND_ADDRESS=127.0.0.1\nPOSTGRES_PORT=5432\n"
    )
    if not env_file.exists() and data_dir.exists() and any(data_dir.iterdir()):
        raise ValueError(f"Data already exists at {data_dir}, but {env_file} is missing; restore its settings instead of generating new credentials")
    try:
        descriptor = os.open(env_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        return False
    with os.fdopen(descriptor, "w") as handle:
        handle.write(content)
    return True


def connection_environment(config):
    service = config["services"]["postgres"]
    environment = service["environment"]
    port = next(port for port in service["ports"] if int(port["target"]) == 5432)
    host = port.get("host_ip", "127.0.0.1")
    if host in ("0.0.0.0", "::", ""):
        host = "127.0.0.1"
    if ":" in host:
        host = f"[{host}]"
    user = quote(str(environment["POSTGRES_USER"]), safe="")
    password = quote(str(environment["POSTGRES_PASSWORD"]), safe="")
    base = f"postgresql://{user}:{password}@{host}:{port['published']}/"
    return f"export SHARED_DEV_DB_BASE_URL={shlex.quote(base)}\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env-file", type=Path, default=ROOT / ".env")
    parser.add_argument("--data-dir", type=Path, default=ROOT / "data",
                        help="data directory for new settings; existing settings are preserved")
    parser.add_argument("--connection-file", type=Path)
    parser.add_argument("--require-data-dir", action="store_true",
                        help="refuse existing settings pointing to a different data directory")
    args = parser.parse_args()
    env_file = args.env_file.expanduser().resolve()
    data_dir = args.data_dir.expanduser().resolve()
    connection_file = (args.connection_file or Path(str(env_file) + ".connection")).expanduser().resolve()
    if connection_file == env_file:
        parser.error("connection file must differ from the settings file")
    created = initialize(env_file, data_dir)
    env_file.chmod(0o600)
    # Ask Compose to parse dotenv and apply interpolation. Do not source settings
    # as shell code, or print the resolved configuration (it contains secrets).
    compose = [os.environ.get("CONTAINER_ENGINE", "docker"), "compose",
               "--project-directory", str(ROOT), "--env-file", str(env_file)]
    result = subprocess.run(compose + ["config", "--format", "json"],
                            check=True, capture_output=True, text=True)
    config = json.loads(result.stdout)
    if args.require_data_dir:
        volumes = config["services"]["postgres"]["volumes"]
        volume = next(v for v in volumes if v["target"] == "/var/lib/postgresql")
        if Path(volume["source"]).resolve() != data_dir:
            raise ValueError(f"Existing settings use a different data directory; review {env_file} before continuing")
    write_private(connection_file, connection_environment(config))
    print(f"{'Created' if created else 'Preserved'} {env_file}; connection environment: {connection_file}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, StopIteration, subprocess.CalledProcessError) as error:
        # CalledProcessError's repr contains only the command, not secret output.
        raise SystemExit(f"Database configuration failed: {error}")
