"""Run against a running Permission Bell. Never prints the shared token."""
import http.client
import json
from pathlib import Path
TOKEN = Path(".local/bridge-token").read_text().strip()
ORIGIN = 'chrome-extension://permission-bell-integration-test'
def request(method, path, body=None, token=TOKEN, origin=ORIGIN):
    connection = http.client.HTTPConnection('127.0.0.1', 18473, timeout=5)
    headers = {'Content-Type': 'application/json', 'X-Permission-Bell-Token': token, 'Origin': origin}
    connection.request(method, path, body, headers)
    response = connection.getresponse()
    result = response.status
    response.read()
    connection.close()
    return result
assert request('OPTIONS', '/event') == 204
valid = json.dumps({'tab': 999999999, 'host': 'chatgpt.com', 'pending': False})
assert request('POST', '/event', valid) == 200
assert request('POST', '/event', valid, token='wrong') == 403
assert request('POST', '/event', valid, origin='https://example.com') == 403
assert request('POST', '/event', json.dumps({'tab': 1, 'host': 'example.com', 'pending': True})) == 400
assert request('POST', '/event', '{broken') == 400
assert request('POST', '/wrong', valid) == 403
print('Bridge: authenticated event, CORS preflight, invalid token/origin/host/JSON/path passed')
