import contextlib
import io
import os
import signal
import subprocess
import unittest
from unittest.mock import Mock, patch

import bench


class BenchmarkGuardChecks(unittest.TestCase):
    def simulate(self, *, pressure=None, rss=0, size=0, elapsed=0, exited=None, **limits):
        process = Mock(pid=123456, returncode=0)
        process.poll.return_value = exited
        with contextlib.ExitStack() as stack:
            directory = stack.enter_context(bench.tempfile.TemporaryDirectory())
            make_temp = bench.tempfile.mkstemp
            stack.enter_context(patch.object(bench.tempfile, "mkstemp",
                side_effect=lambda **kwargs: make_temp(dir=directory, **kwargs)))
            stack.enter_context(contextlib.redirect_stderr(io.StringIO()))
            stack.enter_context(patch.object(bench, "host_pressure", side_effect=pressure or [None, None]))
            stack.enter_context(patch.object(bench, "group_rss", return_value=rss))
            stack.enter_context(patch.object(bench.os, "fstat", return_value=Mock(st_size=size)))
            stack.enter_context(patch.object(bench.time, "monotonic", side_effect=[0, elapsed]))
            launch = stack.enter_context(patch.object(bench.subprocess, "Popen", return_value=process))
            stop = stack.enter_context(patch.object(bench, "stop_group"))
            try:
                bench.run(["controlled-child"], **limits)
            except RuntimeError as error:
                return str(error), launch, stop
            return None, launch, stop

    def test_pressure_refuses_launch(self):
        error, launch, stop = self.simulate(pressure=["warning"])
        self.assertIn("not started", error)
        launch.assert_not_called()
        stop.assert_not_called()

    def test_pressure_stops_owned_process(self):
        error, launch, stop = self.simulate(pressure=[None, "warning"])
        self.assertIn("warning", error)
        stop.assert_called_once_with(launch.return_value)

    def test_memory_limit(self):
        error, launch, stop = self.simulate(rss=2 * 1048576, memory_mib=1)
        self.assertIn("RSS", error)
        self.assertTrue(launch.call_args.kwargs["start_new_session"])
        stop.assert_called_once_with(launch.return_value)

    def test_output_limit(self):
        error, launch, stop = self.simulate(size=2 * 1048576, output_mib=1)
        self.assertIn("Output", error)
        stop.assert_called_once_with(launch.return_value)

    def test_deadline(self):
        error, launch, stop = self.simulate(elapsed=2, timeout=1)
        self.assertIn("Time", error)
        stop.assert_called_once_with(launch.return_value)

    def test_normal_exit(self):
        error, launch, stop = self.simulate(exited=0)
        self.assertIsNone(error)
        stop.assert_called_once_with(launch.return_value)

    def test_concurrent_launch_refused(self):
        with bench.benchmark_lock(), self.assertRaisesRegex(RuntimeError, "Another"):
            with bench.benchmark_lock():
                self.fail("Two benchmark locks were acquired")

    def test_rss_includes_only_owned_group(self):
        with patch.object(subprocess, "check_output", return_value="100 1024\n100 2048\n200 999999\n"):
            self.assertEqual(bench.group_rss(100), 3 * 1048576)

    def test_group_shutdown_escalates(self):
        process = Mock(pid=123456)
        process.wait.side_effect = [subprocess.TimeoutExpired("child", 0.5), 0]
        with patch.object(os, "killpg") as kill:
            bench.stop_group(process)
        self.assertEqual(kill.call_args_list[0].args, (123456, signal.SIGTERM))
        self.assertEqual(kill.call_args_list[1].args, (123456, signal.SIGKILL))
        self.assertEqual(process.wait.call_count, 2)


if __name__ == "__main__":
    unittest.main()
