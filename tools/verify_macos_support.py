"""Mac 适配离线验证：不使用真实凭据，不访问云端、不创建直播会话。"""
from __future__ import annotations

import asyncio
import json
import pathlib
import sys
import unittest
from unittest import mock

import httpx
import websockets

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from src import llm
from src.vidu import client as vidu
from tools.douyin_relay import relay


class MacSupportChecks(unittest.IsolatedAsyncioTestCase):
    def test_missing_vidu_key_stops_before_request(self):
        with mock.patch.object(vidu, "CONF", {"api_key": "  "}):
            with self.assertRaisesRegex(RuntimeError, "未配置 Vidu API Key"):
                vidu._headers()
        with mock.patch.object(vidu, "CONF", {"api_key": " vda_offline_test "}):
            self.assertEqual(vidu._headers()["Authorization"], "Token vda_offline_test")

    async def test_empty_token_limit_uses_valid_default(self):
        requests = []

        def answer(request):
            requests.append(json.loads(request.content))
            return httpx.Response(200, text='data: {"choices":[{"delta":{"content":"你好"}}]}\n\ndata: [DONE]\n\n')

        for value, expected in (("", 300), (None, 300), (128, 128)):
            client = llm.LLMClient(lambda: {"max_tokens": value})
            with mock.patch.object(client, "api_key", return_value="offline-test-key"):
                async_client = httpx.AsyncClient(transport=httpx.MockTransport(answer))
                with mock.patch.object(llm.httpx, "AsyncClient", return_value=async_client):
                    self.assertEqual([piece async for piece in client.stream("你好")], ["你好"])
            self.assertEqual(requests[-1]["max_tokens"], expected)

    async def test_local_websocket_message_reaches_http_bridge(self):
        received = asyncio.get_running_loop().create_future()
        ws_paths = []

        async def bridge(reader, writer):
            try:
                headers = await reader.readuntil(b"\r\n\r\n")
                length = next(int(line.split(b":", 1)[1]) for line in headers.split(b"\r\n")
                              if line.lower().startswith(b"content-length:"))
                body = json.loads(await reader.readexactly(length))
                self.assertTrue(headers.startswith(b"POST /api/danmaku "))
                writer.write(b'HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\n{"ok":true}')
                await writer.drain()
                received.set_result(body)
            except Exception as exc:
                if not received.done():
                    received.set_exception(exc)
            finally:
                writer.close()
                await writer.wait_closed()

        async def collector(ws):
            ws_paths.append(ws.request.path)
            await ws.send(json.dumps({"method": "WebcastChatMessage",
                                     "user": {"nickname": "本地测试"}, "content": "你好"}))
            await ws.wait_closed()

        http_server = await asyncio.start_server(bridge, "127.0.0.1", 0)
        http_port = http_server.sockets[0].getsockname()[1]
        async with http_server, websockets.serve(collector, "127.0.0.1", 0) as ws_server:
            ws_port = ws_server.sockets[0].getsockname()[1]
            task = asyncio.create_task(relay("offline-test", f"ws://127.0.0.1:{ws_port}",
                                             f"http://127.0.0.1:{http_port}", False))
            try:
                body = await asyncio.wait_for(received, 5)
                self.assertEqual(ws_paths, ["/ws/offline-test"])
                self.assertEqual(body, {"nick": "本地测试", "content": "你好", "text": "你好",
                                        "platform": "抖音", "kind": ""})
            finally:
                task.cancel()
                await asyncio.gather(task, return_exceptions=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
