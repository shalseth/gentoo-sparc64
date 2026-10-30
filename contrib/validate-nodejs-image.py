#!/usr/bin/env python3
"""Exercise a Portage-staged Node installation without merging it into the host."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--image', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--node-sha256')
args = parser.parse_args()
prefix = args.image.resolve() / 'usr'
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
node = prefix / 'bin/node'
sha = hashlib.file_digest(node.open('rb'), 'sha256').hexdigest()
assert not args.node_sha256 or sha == args.node_sha256
fixtures = list((prefix / 'share/doc').glob('nodejs-*/validation'))
assert len(fixtures) == 1
fixtures = fixtures[0]
config = (args.image.resolve() / 'etc/npm/npmrc').read_text()
assert 'nodedir=/usr\n' in config and 'prefix=/usr/local\n' in config
(out / 'npmrc').write_text(f'nodedir={prefix}\nprefix={out}/global\n')
(out / 'empty-user-npmrc').touch()
(out / 'home').mkdir()
env = dict(os.environ, PATH=str(prefix / 'bin') + ':' + os.defpath, HOME=str(out / 'home'),
    NPM_CONFIG_GLOBALCONFIG=str(out / 'npmrc'), npm_config_userconfig=str(out / 'empty-user-npmrc'),
    npm_config_cache=str(out / 'npm-cache'), npm_config_audit='false', npm_config_fund='false',
    npm_config_update_notifier='false', SPARC64_EXPECT_NODE=str(node))
for name in ['NODE_OPTIONS', 'NODE_PATH', 'npm_config_nodedir', 'NPM_CONFIG_NODEDIR', 'npm_config_prefix']:
    env.pop(name, None)
record = dict(passed=False, node_sha256=sha, prefix=str(prefix), results=[])


def run(name, command, cwd=None, marker=None):
    started = time.monotonic()
    with (out / (name + '.log')).open('w') as stream:
        p = subprocess.run(command, cwd=cwd or out, env=env, stdout=stream,
                           stderr=subprocess.STDOUT, timeout=180)
    text = (out / (name + '.log')).read_text()
    result = dict(name=name, command=command, seconds=time.monotonic()-started,
                  exit_code=p.returncode, passed=p.returncode == 0 and (marker is None or marker in text))
    record['results'].append(result)
    (out / 'validation.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps(result), flush=True)
    assert result['passed'], text[-3000:]


run('runtime', [str(node), '-e', "const a=require('node:assert/strict');a.equal(process.arch,'sparc64');a.equal(require('node:os').endianness(),'BE');a.equal(process.features.typescript,'strip');a.equal(typeof Temporal,'object');a.equal(process.config.variables.node_use_ffi,true);console.log(process.versions)"])
for name in ['npm', 'npx']:
    run(name + '-version', [str(prefix / 'bin' / name), '--version'])
addon = out / 'addon'
shutil.copytree(fixtures / 'addon', addon)
run('addon-build-system-config', [str(prefix / 'bin/npm'), 'install', '--offline'], cwd=addon)
assert str(prefix / 'include/node') in (out / 'addon-build-system-config.log').read_text()
run('addon-execute', [str(node), '--expose-gc', str(addon / 'test.cjs')], marker='INSTALLED_NATIVE_ADDON_OK')
cli = out / 'cli'
shutil.copytree(fixtures / 'cli', cli)
run('cli-pack', [str(prefix / 'bin/npm'), 'pack', '--offline'], cwd=cli)
consumer = out / 'consumer'
consumer.mkdir()
(consumer / 'package.json').write_text('{"name":"portage-node-smoke","private":true}\n')
run('cli-install', [str(prefix / 'bin/npm'), 'install', '--offline', str(cli / 'sparc64-installed-cli-1.0.0.tgz')], cwd=consumer)
run('npx-execute', [str(prefix / 'bin/npx'), '--offline', '--no', 'sparc64-installed-cli', 'SPARC64'], cwd=consumer, marker='INSTALLED_NPX_CLI_OK')
run('typescript-workers-fetch', [str(node), str(fixtures / 'typescript/main.ts')], marker='TYPESCRIPT_APPLICATION_OK')
run('temporal-workers', [str(node), '--expose-gc', '--verify-heap', str(fixtures / 'temporal.cjs')], marker='"passed":true')
record['passed'] = True
(out / 'validation.json').write_text(json.dumps(record, indent=2) + '\n')
print('PORTAGE_NODE_IMAGE_VALIDATED', flush=True)
