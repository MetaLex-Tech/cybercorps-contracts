import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("safe_let_runner", Path(__file__).resolve().parents[1] / "script/upgrade-safe-let-image.py")
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class SafeLetImageRunnerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.patcher = patch.object(runner, "ROOT", self.root)
        self.patcher.start()
        self.addCleanup(self.patcher.stop)
        self.commands = []
        self.args = argparse.Namespace(chains=list(runner.CHAINS), rpc=[], sender="0x" + "11" * 20,
                                       account="test-account", ledger=False, broadcast=False)

    def execute(self, command, **kwargs):
        self.commands.append(command)
        index = command.index("--sig")
        chain_id = command[index + 2]
        path = self.root / command[index + 3]
        path.write_text(json.dumps({"version": "1.0", "chainId": chain_id, "transactions": [
            {"to": "0x" + "22" * 20, "value": "0", "data": "0x8a5dc582" + "00" * 32}]}))
        return subprocess.CompletedProcess(command, 0, "simulated", "")

    def testDefaultsSimulateAllFourChainsWithSeparateBatches(self):
        directory = runner.prepare(self.args, self.execute)
        self.assertEqual(len(self.commands), 4)
        self.assertFalse(any("--broadcast" in c for c in self.commands))
        manifest = json.loads((directory / "manifest.json").read_text())
        self.assertEqual([s["chainId"] for s in manifest["steps"]], [1, 8453, 42161, 4663])
        self.assertTrue(all(s["status"] == "simulated" for s in manifest["steps"]))
        self.assertEqual(len(list(directory.glob("*-simulation.json"))), 4)
        for name, command in zip(runner.CHAINS, self.commands):
            self.assertEqual(command[command.index("--rpc-url") + 1], runner.CHAINS[name][1])
            self.assertIn("test-account", command)

    def testAllPreflightsPrecedeBroadcastAndOutputStaysUnverified(self):
        self.args.broadcast = True
        directory = runner.prepare(self.args, self.execute)
        self.assertEqual(["--broadcast" in c for c in self.commands], [False] * 4 + [True] * 4)
        self.assertTrue(all("--slow" in c for c in self.commands[4:]))
        self.assertEqual(len(list(directory.glob("*-unverified.json"))), 4)
        manifest = json.loads((directory / "manifest.json").read_text())
        self.assertEqual(manifest["safeExecution"], "not submitted")
        self.assertTrue(all(s["status"] == "broadcast-complete-unverified" for s in manifest["steps"][4:]))

    def testFailedPreflightPreventsEveryBroadcast(self):
        self.args.broadcast = True
        def fail(command, **kwargs):
            self.execute(command, **kwargs)
            return subprocess.CompletedProcess(command, 1, "", "wrong owner")
        with self.assertRaises(RuntimeError):
            runner.prepare(self.args, fail)
        self.assertEqual(len(self.commands), 1)
        self.assertNotIn("--broadcast", self.commands[0])

    def testFailedBroadcastStopsRemainingChains(self):
        self.args.broadcast = True
        def fail(command, **kwargs):
            result = self.execute(command, **kwargs)
            if "--broadcast" in command:
                result.returncode = 1
            return result
        with self.assertRaises(RuntimeError):
            runner.prepare(self.args, fail)
        self.assertEqual(len(self.commands), 5)
        manifest = json.loads(next(self.root.rglob("manifest.json")).read_text())
        self.assertEqual(manifest["steps"][-1]["status"], "failed")
        self.assertTrue((self.root / manifest["steps"][-1]["batch"]).exists())

    def testWrongChainBatchIsRejected(self):
        def wrong_chain(command, **kwargs):
            result = self.execute(command, **kwargs)
            index = command.index("--sig")
            path = self.root / command[index + 3]
            batch = json.loads(path.read_text())
            batch["chainId"] = "31337"
            path.write_text(json.dumps(batch))
            return result
        with self.assertRaisesRegex(RuntimeError, "chain mismatch"):
            runner.prepare(self.args, wrong_chain)
        self.assertEqual(len(self.commands), 1)

    def testSubsetRpcOverrideAndLedger(self):
        self.args.chains = ["rhc"]
        self.args.rpc = ["rhc=http://127.0.0.1:8545"]
        self.args.account = None
        self.args.ledger = True
        runner.prepare(self.args, self.execute)
        self.assertEqual(len(self.commands), 1)
        self.assertIn("http://127.0.0.1:8545", self.commands[0])
        self.assertIn("--ledger", self.commands[0])
        self.assertNotIn("--account", self.commands[0])

    def testInvalidSelectionRefusesBeforeExecuting(self):
        for chains, rpc in [(["eth", "eth"], []), (["eth"], ["unknown=ethereum"]), (["eth"], ["eth="])]:
            self.args.chains, self.args.rpc = chains, rpc
            with self.assertRaises(ValueError):
                runner.prepare(self.args, self.execute)
        self.assertEqual(self.commands, [])

    def testInvalidOwnerCallOrNonzeroValueIsRejected(self):
        path = self.root / "batch.json"
        for tx in [{"to": "0x" + "22" * 20, "value": "1", "data": "0x8a5dc582"},
                   {"to": "0x" + "22" * 20, "value": "0", "data": "0xdeadbeef"}]:
            path.write_text(json.dumps({"version": "1.0", "chainId": "1", "transactions": [tx]}))
            with self.assertRaises(ValueError):
                runner.validate_batch(path, 1)


if __name__ == "__main__":
    unittest.main()
