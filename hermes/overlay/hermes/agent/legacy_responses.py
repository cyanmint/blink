# HermesLink AI-generated glue code; created by cyanmint's coding agent.
# AI-generated content has no copyright holder and is not subject to copyright.
import json
import threading
from types import SimpleNamespace


_HTTP_LOCK = threading.RLock()


class _ResponseStream:
    def __init__(self, events):
        self._events = events

    def __iter__(self):
        yield from self._events

    def close(self):
        return None


def _as_namespace(value):
    """Convert JSON response items to objects expected by the Responses event consumer."""
    if isinstance(value, dict):
        return SimpleNamespace(**{key: _as_namespace(item) for key, item in value.items()})
    if isinstance(value, list):
        return [_as_namespace(item) for item in value]
    return value


class _ResponsesCompat:
    def __init__(self, client):
        self._client = client

    def create(self, **kwargs):
        import httpx
        payload = dict(kwargs)
        extra = payload.pop("extra_body", None)
        if isinstance(extra, dict):
            for key, value in extra.items():
                payload.setdefault(key, value)
        payload.pop("stream_options", None)
        timeout = payload.pop("timeout", None)
        payload.pop("stream", None)
        base = str(getattr(self._client, "base_url", "")).rstrip("/")
        url = base + "/responses"
        headers = dict(getattr(self._client, "default_headers", {}) or {})
        headers.update(getattr(self._client, "_custom_headers", {}) or {})
        headers = {key: value for key, value in headers.items() if isinstance(value, (str, bytes))}
        api_key = getattr(self._client, "api_key", None)
        if api_key and "Authorization" not in headers:
            headers["Authorization"] = "Bearer " + api_key
        headers.setdefault("Content-Type", "application/json")
        transport = getattr(self._client, "_client", None)
        if transport is None:
            transport = httpx.Client()
        with _HTTP_LOCK:
            response = transport.post(url, headers=headers, json=payload, timeout=timeout)
        if response.status_code >= 400:
            body = response.text
            raise RuntimeError("HTTP %s: %s" % (response.status_code, body))
        result = response.json()
        events = []
        output = result.get("output")
        for index, item in enumerate(output if isinstance(output, list) else []):
            if not isinstance(item, dict):
                continue
            events.append({
                "type": "response.output_item.added",
                "output_index": index,
                "item": _as_namespace(item),
            })
            if item.get("type") == "message":
                for part in item.get("content") or []:
                    text = part.get("text") if isinstance(part, dict) and part.get("type") == "output_text" else None
                    if isinstance(text, str) and text:
                        events.append({"type": "response.output_text.delta", "delta": text})
            events.append({
                "type": "response.output_item.done",
                "output_index": index,
                "item": _as_namespace(item),
            })
        events.append({"type": "response.completed", "response": _as_namespace(result)})
        return _ResponseStream(events)


def install(client):
    cls = type(client)
    if not hasattr(cls, "responses"):
        setattr(cls, "responses", property(lambda instance: _ResponsesCompat(instance)))
    return client
