#!/usr/bin/env python3
"""Behavior tests for the guest side of macOS Wi-Fi status mirroring."""

from __future__ import annotations

import importlib.util
from importlib.machinery import SourceFileLoader
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import subprocess
import sys


BRIDGE_PATH = (
    Path(__file__).resolve().parents[1]
    / "guest/package/try-omarchy/files/usr/bin/omarchy-native-hostnet-bridge"
)
WIFI_PATH = (
    Path(__file__).resolve().parents[1]
    / "guest/package/try-omarchy/files/usr/bin/omarchy-host-wifi"
)


def load(path: Path, name: str):
    loader = SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    # Python 3.14 dataclasses/modules expect the name in sys.modules for some loaders.
    import sys

    sys.modules[name] = module
    loader.exec_module(module)
    return module


bridge = load(BRIDGE_PATH, "omarchy_native_hostnet_bridge")
wifi_cli = load(WIFI_PATH, "omarchy_host_wifi")


def sample_wifi(**overrides):
    message = {
        "type": "wifi",
        "powered": True,
        "associated": True,
        "ssid": "HomeNet",
        "rssiDbm": -55,
        "noiseDbm": -92,
        "snrDb": 37,
        "txRateMbps": 600.0,
        "channel": 149,
        "channelWidthMhz": 80,
        "band": "5g",
        "security": "wpa3-personal",
        "interface": "en0",
        "ssidUnavailable": False,
    }
    message.update(overrides)
    return message


class DecodeTests(unittest.TestCase):
    def test_accepts_wire_contract(self):
        line = json.dumps(sample_wifi(), separators=(",", ":")).encode()
        decoded = bridge.decode_wifi(line)
        self.assertEqual(decoded["ssid"], "HomeNet")
        self.assertEqual(decoded["snrDb"], 37)

    def test_rejects_unknown_keys_and_types(self):
        with self.assertRaises(ValueError):
            bridge.decode_wifi(b'{"type":"wifi"}')
        bad = sample_wifi()
        bad["extra"] = 1
        with self.assertRaises(ValueError):
            bridge.decode_wifi(json.dumps(bad).encode())
        bad = sample_wifi(rssiDbm=True)
        with self.assertRaises(ValueError):
            bridge.decode_wifi(json.dumps(bad).encode())
        bad = sample_wifi(powered="yes")
        with self.assertRaises(ValueError):
            bridge.decode_wifi(json.dumps(bad).encode())


    def test_optional_radio_fields_accept_older_hosts_and_reject_invalid_values(self):
        decoded = bridge.decode_wifi(json.dumps(sample_wifi(ipAddress="192.0.2.10", bssid=None, phyMode="802.11ax")).encode())
        self.assertEqual(decoded['ipAddress'], '192.0.2.10')
        mode = bridge.decode_wifi(json.dumps(sample_wifi(networkMode="bridged", bridgeInterface="en0")).encode())
        self.assertEqual(mode['bridgeInterface'], 'en0')
        with self.assertRaises(ValueError):
            bridge.decode_wifi(json.dumps(sample_wifi(networkMode="invalid")).encode())
        self.assertNotIn('ipAddress', bridge.decode_wifi(json.dumps(sample_wifi()).encode()))
        for key in ('ipAddress', 'bssid', 'phyMode', 'networkMode', 'bridgeInterface'):
            with self.subTest(key=key), self.assertRaises(ValueError):
                bridge.decode_wifi(json.dumps(sample_wifi(**{key: 123})).encode())


class BluetoothTests(unittest.TestCase):
    def test_device_schema_and_action_allowlist(self):
        import uuid
        message = {"type": "bluetooth", "authorization": "allowed", "powered": True,
                   "devices": [{"id": "AA:BB:CC:DD:EE:FF", "name": "<b>Example headphones</b>", "connected": False, "kind": "audio"}]}
        self.assertEqual(bridge.decode_bluetooth(message), message)
        for bad in [dict(message, authorization="unknown"), dict(message, powered=1),
                    dict(message, devices=message['devices'] * 2)]:
            with self.assertRaises(ValueError):
                bridge.decode_bluetooth(bad)
        for action in ['connect', 'disconnect']:
            command = {"type": "bluetooth-action", "id": str(uuid.uuid4()), "action": action, "device": "AA:BB:CC:DD:EE:FF"}
            self.assertEqual(bridge.decode_action(json.dumps(command).encode()), command)
        for action in ['power', 'pair', 'forget', 'shell']:
            with self.assertRaises(ValueError):
                bridge.decode_action(json.dumps({"type": "bluetooth-action", "id": str(uuid.uuid4()), "action": action}).encode())


class BluetoothTransportTests(unittest.TestCase):
    def test_multiplexed_actions_and_wifi_freshness(self):
        import pty
        import select
        import socket
        import tty
        import time
        master, slave = pty.openpty()
        tty.setraw(slave)
        with tempfile.TemporaryDirectory() as tmp:
            env = dict(os.environ, XDG_RUNTIME_DIR=tmp, OMARCHY_HOSTNET_PORT=os.ttyname(slave))
            process = subprocess.Popen([sys.executable, str(BRIDGE_PATH)], env=env, stderr=subprocess.DEVNULL)
            directory = Path(tmp)/'try-omarchy-hostnet'
            def wait_for(predicate, seconds=3):
                deadline = time.monotonic()+seconds
                while time.monotonic() < deadline:
                    if predicate(): return
                    time.sleep(0.02)
                self.fail('bridge did not reach expected state')
            bluetooth = {"type":"bluetooth", "authorization":"allowed", "powered":True, "devices":[]}
            def send(message):
                os.write(master, json.dumps(message).encode()+b'\n')
            try:
                wait_for(lambda: (directory/'control.sock').exists())
                self.assertTrue(select.select([master], [], [], 2)[0])
                self.assertEqual(json.loads(os.read(master, 4096)), {"type":"refresh", "services":["wifi", "bluetooth"]})
                send(sample_wifi()); send(bluetooth)
                wait_for(lambda: (directory/'wifi.json').exists() and (directory/'bluetooth.json').exists())
                client = subprocess.Popen([sys.executable, str(BRIDGE_PATH.parent/'omarchy-host-bluetooth'), 'connect', 'AA:BB:CC:DD:EE:FF'], env=env, stdout=subprocess.PIPE, text=True)
                self.assertTrue(select.select([master], [], [], 2)[0])
                command = json.loads(os.read(master, 4096))
                self.assertEqual(command['action'], 'connect')
                send({'type':'bluetooth-result', 'id':command['id'], 'ok':False, 'message':'Device is not paired'})
                output, _ = client.communicate(timeout=3)
                self.assertEqual(client.returncode, 1)
                self.assertEqual(json.loads(output)['message'], 'Device is not paired')
                with socket.socket(socket.AF_UNIX) as invalid:
                    invalid.settimeout(2); invalid.connect(str(directory/'control.sock'))
                    invalid.sendall(b'{"type":"bluetooth-action","id":5,"action":"refresh"}\n')
                    self.assertFalse(json.loads(invalid.recv(4096))['ok'])
                self.assertIsNone(process.poll())
                # Bluetooth traffic must not keep an old Wi-Fi snapshot alive.
                deadline = time.monotonic()+16
                while time.monotonic() < deadline:
                    send(bluetooth)
                    time.sleep(1)
                wait_for(lambda: not (directory/'wifi.json').exists())
                self.assertTrue((directory/'bluetooth.json').exists())
                self.assertIsNone(process.poll())
            finally:
                process.terminate(); process.wait(timeout=3)
                os.close(master); os.close(slave)


class StateFileTests(unittest.TestCase):
    def test_write_and_cli(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.environ["XDG_RUNTIME_DIR"] = tmp
            bridge.write_wifi(sample_wifi())
            path = Path(tmp) / "try-omarchy-hostnet" / "wifi.json"
            self.assertTrue(path.is_file())
            loaded = wifi_cli.load()
            self.assertIsNotNone(loaded)
            self.assertIn("HomeNet", wifi_cli.human(loaded))
            waybar = wifi_cli.waybar(loaded)
            self.assertEqual(waybar["class"], "good")


class WidgetModelTests(unittest.TestCase):
    def test_connection_states_and_untrusted_ssid_are_plain_text(self):
        model = BRIDGE_PATH.parents[1] / "share/try-omarchy/host-wifi/WifiModel.js"
        script = model.read_text() + r"""
const assert = require('assert');
assert.equal(view(null).label, 'Unavailable');
assert.equal(view({type:'wifi', powered:false}).label, 'Off');
assert.equal(view({type:'wifi', powered:true, associated:false}).label, 'Disconnected');
assert.equal(view({type:'wifi', powered:true, associated:true, ssid:null}).label, 'Connected');
assert.equal(display(0, ' dB'), '0 dB');
assert.equal(display(null, ' dB'), '--');
assert.equal(radio({associated:true, band:'5g', phyMode:'802.11ax'}), '5 GHz · 802.11ax');
assert.equal(channel({associated:true, channel:52, channelWidthMhz:80}), '52 (80 MHz)');
assert.equal(quality({associated:true, rssiDbm:-60}), 'Good');
assert.equal(connection({networkMode:'nat',interface:'en0'}).showRadio, true);
assert.equal(connection({networkMode:'nat',interface:'en0'}).bridgedWifi, false);
assert.equal(connection({networkMode:'bridged',bridgeInterface:'en0',interface:'en0'}).bridgedWifi, true);
assert.equal(connection({networkMode:'bridged',bridgeInterface:'en7',interface:'en0'}).showRadio, false);
assert.equal(connection(null).bridgedWifi, false);
let samples = history([], {associated:true, rssiDbm:-55}, 1000);
assert.equal(history(samples, {associated:true, rssiDbm:-55}, 2000).length, 1);
samples = history(samples, {associated:true, rssiDbm:-55}, 6000);
assert.equal(samples.length, 2); // steady signal still produces history
samples = history(samples, null, 11000);
assert.equal(samples[2].rssi, null); // disconnected is a gap, not a made-up value
samples = history(samples, {associated:true, rssiDbm:-60}, 130000);
assert.equal(samples.length, 2); // samples older than two minutes expire

for (const [rssi, bars] of [[-50,4],[-60,3],[-70,2],[-80,1],[null,0]]) {
  const result = view({type:'wifi', powered:true, associated:true, ssid:'<b>Home</b>\n', rssiDbm:rssi});
  assert.equal(result.bars, bars);
  assert.equal(result.label, '<b>Home</b> ');
}
"""
        subprocess.run(['node', '-e', script], check=True)

class SetupTests(unittest.TestCase):
    def test_registration_preserves_layout_and_respects_later_removal(self):
        setup = load(BRIDGE_PATH.parent / "omarchy-host-wifi-setup", "host_wifi_setup")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'widget'; source.mkdir()
            config = root / 'config'; state = root / 'state'
            settings = config / 'omarchy/shell.json'
            settings.parent.mkdir(parents=True)
            original = '{"bar":{"layout":{"right":[{"id":"omarchy.network"}]}},"plugins":[]}'
            settings.write_text(original)
            real_exists = Path.exists
            def exists(path):
                return True if str(path) == '/dev/virtio-ports/dev.tryomarchy.hostnet' else real_exists(path)
            with patch.dict(os.environ, XDG_CONFIG_HOME=str(config), XDG_STATE_HOME=str(state)), \
                 patch.object(setup, 'SOURCE', source), patch.object(Path, 'exists', exists), \
                 patch.object(setup.subprocess, 'run') as run:
                self.assertEqual(setup.main(), 0)
                self.assertEqual(run.call_count, 3)
                self.assertEqual(settings.read_text(), original)
                self.assertEqual((state/'try-omarchy/shell.json.before-host-wifi').read_text(), original)
                run.reset_mock()
                self.assertEqual(setup.main(), 0)
                run.assert_called_once_with(["/usr/bin/omarchy-vm-network-setup"], check=True, timeout=30)

if __name__ == "__main__":
    raise SystemExit(unittest.main(verbosity=2))
