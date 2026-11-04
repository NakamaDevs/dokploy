#!/usr/bin/env python3
"""Check compiled paths and real Docker/Compose mounts in a disposable directory."""
import argparse
import json
import pathlib
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("image")
parser.add_argument("--host-root", default=str(pathlib.Path.home() / ".local/share/dokploy"))
args = parser.parse_args()


def docker(*command):
    return subprocess.check_output(["docker", *command], text=True, timeout=60).strip()


with tempfile.TemporaryDirectory(prefix="dokploy-mount-check-", dir=args.host_root) as root:
    folder = pathlib.Path(root)
    (folder / "compose").mkdir()
    (folder / "compose/probe.txt").write_text("macos-bind-mount-ok")
    code = """const {paths}=require('/app/node_modules/@dokploy/server/dist/constants/index.js');
console.log(JSON.stringify({local:paths().COMPOSE_PATH,remote:paths(true).COMPOSE_PATH}));"""
    output = docker("run", "--rm", "--network", "none", "--entrypoint", "node",
                    "-e", "DOKPLOY_HOST_ROOT_PATH=" + root, args.image, "-e", code)
    paths = json.loads(output.splitlines()[-1])
    assert paths == {"local": root + "/compose", "remote": "/etc/dokploy/compose"}, paths
    probe_name = folder.name
    try:
        for _ in range(3):
            content = docker("run", "--rm", "--name", probe_name, "--network", "none",
                             "--entrypoint", "cat", "--mount",
                             "type=bind,source=" + paths["local"] + ",target=/probe,readonly",
                             args.image, "/probe/probe.txt")
            assert content == "macos-bind-mount-ok", content
        config = {"services": {"probe": {"image": args.image, "network_mode": "none",
                  "entrypoint": ["cat", "/probe/probe.txt"],
                  "volumes": ["./compose:/probe:ro"]}}}
        compose_file = folder / "compose.json"
        compose_file.write_text(json.dumps(config))
        content = docker("compose", "-p", probe_name, "-f", str(compose_file),
                         "run", "--rm", "--no-deps", "-T", "--name", probe_name, "probe")
        assert content == "macos-bind-mount-ok", content
        print("PASS compiled paths, three bind-mount lifecycles, and Compose relative mount")
    finally:
        subprocess.run(["docker", "rm", "-f", probe_name], capture_output=True, timeout=15)
