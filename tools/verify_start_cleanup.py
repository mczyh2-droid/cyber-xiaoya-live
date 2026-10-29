"""会话启动失败的离线回归测试：全部配置和 Vidu 调用使用 mock。"""
from __future__ import annotations

import asyncio
import pathlib
import sys
import unittest
from unittest import mock

import httpx

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from src import engine as engine_module


class FakeSignaling:
    def __init__(self):
        self.ws = None
        self.connect = mock.AsyncMock(side_effect=self._connect)
        self.conn_init = mock.AsyncMock(return_value=True)
        self.hangup = mock.AsyncMock()
        self.close = mock.AsyncMock()

    async def _connect(self):
        self.ws = object()


class StartCleanupChecks(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        config = {"vidu": {"host": "offline.invalid", "api_key": "offline-test"},
                  "tts": {}, "rtc": {}, "session": {"greeting": ""}}
        self.sig = FakeSignaling()
        self.config = self._patch(engine_module.appconf, "load", return_value=config)
        self._patch(engine_module.vu, "configure")
        self.create = self._patch(engine_module.vu, "create_component", new=mock.AsyncMock(
            return_value={"live": {"id": "offline-new-live"}, "managed_rtc": {}}))
        self.get_live = self._patch(engine_module.vu, "get_live", new=mock.AsyncMock(
            side_effect=AssertionError("启动清理不应查询云端")))
        self.factory = self._patch(engine_module.signaling, "ComponentSignaling",
                                   return_value=self.sig)
        self.engine = engine_module.Engine()
        self._patch(self.engine, "_build_body", return_value=(
            {"model": "vidu-s2", "avatar_id": "offline-avatar"}, {"mode": "managed"}))

    def _patch(self, target, name, **kwargs):
        patcher = mock.patch.object(target, name, **kwargs)
        result = patcher.start()
        self.addCleanup(patcher.stop)
        return result

    def assert_failed(self, error):
        self.assertEqual(self.engine.phase, "idle")
        self.assertIsNone(self.engine.sig)
        self.assertEqual(self.engine.rtc, {})
        self.assertEqual(self.engine.error, f"{type(error).__name__}: {error}")
        self.create.assert_awaited_once()
        self.get_live.assert_not_awaited()

    async def assert_start_raises_original(self, error):
        try:
            await self.engine.start()
        except (Exception, asyncio.CancelledError) as caught:
            self.assertIs(caught, error)
        else:
            self.fail("start 必须保留并抛出原异常")
        self.assert_failed(error)

    async def test_connect_failure_without_ws_closes_without_retry(self):
        error = ImportError("offline SOCKS dependency missing")
        self.sig.connect.side_effect = error
        await self.assert_start_raises_original(error)
        self.sig.connect.assert_awaited_once()
        self.sig.conn_init.assert_not_awaited()
        self.sig.hangup.assert_not_awaited()
        self.sig.close.assert_awaited_once()
        self.assertTrue(any("云端会话结束状态未确认" in item["text"]
                            for item in self.engine.transcripts))

    async def test_partial_connect_failure_hangs_up_and_closes(self):
        error = RuntimeError("offline partial connect failure")

        async def partial_connect():
            self.assertIs(self.engine.sig, self.sig)
            self.sig.ws = object()
            raise error

        self.sig.connect.side_effect = partial_connect
        await self.assert_start_raises_original(error)
        self.sig.hangup.assert_awaited_once_with("start_failed")
        self.sig.close.assert_awaited_once()

    async def test_conn_init_failure_hangs_up_and_closes(self):
        error = RuntimeError("offline conn_init failed")
        self.sig.conn_init.side_effect = error
        await self.assert_start_raises_original(error)
        self.sig.connect.assert_awaited_once()
        self.sig.hangup.assert_awaited_once_with("start_failed")
        self.sig.close.assert_awaited_once()

    async def test_conn_init_false_does_not_mark_live(self):
        self.sig.conn_init.return_value = False
        with self.assertRaisesRegex(RuntimeError, "conn_init 未完成"):
            await self.engine.start()
        self.assertEqual(self.engine.phase, "idle")
        self.sig.hangup.assert_awaited_once_with("start_failed")
        self.sig.close.assert_awaited_once()

    async def test_cleanup_errors_preserve_original_and_still_close(self):
        error = RuntimeError("offline initialization error")
        self.sig.conn_init.side_effect = error
        self.sig.hangup.side_effect = RuntimeError("offline hangup failed")
        self.sig.close.side_effect = RuntimeError("offline close failed")
        await self.assert_start_raises_original(error)
        self.sig.hangup.assert_awaited_once()
        self.sig.close.assert_awaited_once()

    async def test_unexpected_cleanup_error_preserves_original(self):
        error = RuntimeError("offline initialization error")
        self.sig.conn_init.side_effect = error
        self._patch(self.engine, "_cleanup_failed_start", new=mock.AsyncMock(
            side_effect=ValueError("offline unexpected cleanup error")))
        await self.assert_start_raises_original(error)

    async def test_cancellation_during_conn_init_waits_for_cleanup(self):
        init_entered = asyncio.Event()
        hangup_entered = asyncio.Event()
        finish_hangup = asyncio.Event()

        async def wait_init(**kwargs):
            init_entered.set()
            await asyncio.Event().wait()

        async def wait_hangup(reason):
            hangup_entered.set()
            await finish_hangup.wait()

        self.sig.conn_init.side_effect = wait_init
        self.sig.hangup.side_effect = wait_hangup
        task = asyncio.create_task(self.engine.start())
        try:
            await asyncio.wait_for(init_entered.wait(), 1)
            task.cancel("offline cancellation")
            await asyncio.wait_for(hangup_entered.wait(), 1)
            task.cancel("offline second cancellation")
            await asyncio.sleep(0)
            self.assertFalse(task.done())
            finish_hangup.set()
            with self.assertRaises(asyncio.CancelledError):
                await asyncio.wait_for(task, 1)
            self.assertEqual(self.engine.phase, "idle")
            self.assertIsNone(self.engine.sig)
            self.sig.hangup.assert_awaited_once_with("start_failed")
            self.sig.close.assert_awaited_once()
        finally:
            finish_hangup.set()
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)

    async def test_create_timeout_does_not_reuse_old_live_or_retry(self):
        self.engine.live_id = "offline-old-live"
        self.engine.rtc = {"token": "offline-old-token"}
        error = httpx.ReadTimeout("offline create timeout")
        self.create.side_effect = error
        await self.assert_start_raises_original(error)
        self.assertEqual(self.engine.live_id, "")
        self.factory.assert_not_called()
        self.sig.connect.assert_not_awaited()
        self.sig.hangup.assert_not_awaited()
        self.assertTrue(any("云端创建结果未确认" in item["text"]
                            for item in self.engine.transcripts))

    async def test_create_cancelled_does_not_reuse_old_live_or_retry(self):
        self.engine.live_id = "offline-old-live"
        error = asyncio.CancelledError("offline create cancelled")
        self.create.side_effect = error
        await self.assert_start_raises_original(error)
        self.assertEqual(self.engine.live_id, "")
        self.factory.assert_not_called()

    async def test_explicit_create_error_does_not_claim_unknown_result(self):
        for message in ("Vidu HTTP 400: offline invalid avatar", "未配置 Vidu API Key"):
            with self.subTest(message=message):
                self.create.reset_mock()
                self.engine.transcripts.clear()
                error = RuntimeError(message)
                self.create.side_effect = error
                await self.assert_start_raises_original(error)
                self.assertFalse(any("云端创建结果未确认" in item["text"]
                                     for item in self.engine.transcripts))

    async def test_success_does_not_cleanup_signaling(self):
        for name in ("_pump", "_watchdog", "_dan_watchdog_loop"):
            self._patch(self.engine, name, new=mock.AsyncMock())
        try:
            result = await self.engine.start()
            self.assertEqual(result["live_id"], "offline-new-live")
            self.assertEqual(self.engine.phase, "live")
            self.assertIs(self.engine.sig, self.sig)
            self.sig.hangup.assert_not_awaited()
            self.sig.close.assert_not_awaited()
        finally:
            tasks = [self.engine._pump_task, self.engine._watch_task, self.engine._dan_wd_task]
            for task in tasks:
                if task is not None:
                    task.cancel()
            await asyncio.gather(*(task for task in tasks if task is not None),
                                 return_exceptions=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
