import importlib.util
import unittest
from pathlib import Path
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "hermes" / "overlay" / "hermes" / "agent" / "legacy_responses.py"
SPEC = importlib.util.spec_from_file_location("hermeslink_legacy_responses_test", MODULE_PATH)
legacy_responses = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(legacy_responses)


def _field(value, name):
    return value.get(name) if isinstance(value, dict) else getattr(value, name, None)


class _FakeHTTPResponse:
    status_code = 200
    text = ""

    def __init__(self, body):
        self._body = body

    def json(self):
        return self._body


class LegacyResponsesToolCallTests(unittest.TestCase):
    def _events(self, body):
        class _Transport:
            def post(self, url, **kwargs):
                self.url = url
                self.kwargs = kwargs
                return _FakeHTTPResponse(body)

        class _Client:
            base_url = "https://example.invalid/v1/"
            default_headers = {}
            _custom_headers = {}
            api_key = "test-key"

            def __init__(self):
                self._client = _Transport()

        client = _Client()
        legacy_responses.install(client)
        events = list(client.responses.create(model="test-model", input=[], stream=True))
        return events, client._client

    def test_function_call_output_is_preserved_as_done_event(self):
        body = {
            "status": "completed",
            "output": [{
                "type": "function_call",
                "id": "fc_terminal_1",
                "call_id": "call_terminal_1",
                "name": "terminal",
                "arguments": "{\"command\":\"pwd\"}",
                "status": "completed",
            }],
        }

        events, transport = self._events(body)

        done_events = [event for event in events if _field(event, "type") == "response.output_item.done"]
        self.assertEqual(len(done_events), 1)
        item = _field(done_events[0], "item")
        self.assertEqual(_field(item, "type"), "function_call")
        self.assertEqual(_field(item, "name"), "terminal")
        self.assertEqual(_field(item, "arguments"), "{\"command\":\"pwd\"}")
        self.assertEqual(_field(done_events[0], "output_index"), 0)
        self.assertNotIn("stream", transport.kwargs["json"])

    def test_message_text_still_emits_delta_and_done_event(self):
        body = {
            "status": "completed",
            "output": [{
                "type": "message",
                "id": "msg_1",
                "role": "assistant",
                "status": "completed",
                "content": [{"type": "output_text", "text": "Done."}],
            }],
        }

        events, _ = self._events(body)

        self.assertIn("response.output_text.delta", [_field(event, "type") for event in events])
        done_events = [event for event in events if _field(event, "type") == "response.output_item.done"]
        self.assertEqual(len(done_events), 1)
        self.assertEqual(_field(_field(done_events[0], "item"), "id"), "msg_1")


if __name__ == "__main__":
    unittest.main()
