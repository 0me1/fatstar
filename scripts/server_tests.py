"""Run only against an ephemeral local Supabase, never against production."""
import concurrent.futures
import json
import os
import re
import sys
import unittest
import urllib.error
import urllib.request
import uuid
from pathlib import Path

config = {}
for line in Path(sys.argv[1]).read_text().splitlines():
    if '=' in line:
        name, value = line.split('=', 1)
        config[name] = value.strip('"')
base = config.get('API_URL', 'http://127.0.0.1:54321')
if not re.match(r'^http://(127\.0\.0\.1|localhost):\d+$', base):
    raise SystemExit('Tests require an isolated loopback Supabase')
anon = config['ANON_KEY']
service = config['SERVICE_ROLE_KEY']
password = 'Local-only-ci-password-428!'

def request(path, payload=None, token=None, method=None, privileged=False):
    key = service if privileged else anon
    headers = {'apikey': key, 'Authorization': 'Bearer ' + (token or key), 'Content-Type': 'application/json', 'Prefer': 'return=representation'}
    req = urllib.request.Request(base + path, data=None if payload is None else json.dumps(payload).encode(), headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            body = response.read()
            return response.status, json.loads(body) if body else None
    except urllib.error.HTTPError as error:
        body = error.read()
        return error.code, json.loads(body) if body else None

def user(email):
    status, result = request('/auth/v1/admin/users', {'email': email, 'password': password, 'email_confirm': True}, privileged=True)
    if status not in (200, 201):
        raise RuntimeError('Cannot create local fixture user')
    uid = result['id']
    status, _ = request('/rest/v1/allowed_users', {'user_id': uid}, privileged=True)
    assert status == 201
    status, session = request('/auth/v1/token?grant_type=password', {'email': email, 'password': password})
    if status != 200:
        detail = session.get('msg') or session.get('error_description') or session.get('message') or session.get('error')
        raise RuntimeError(f'Fixture sign-in failed HTTP {status}: {detail}')
    return uid, session['access_token']

def rpc(token, kind, rid, data, version=0, operation=None, deleted=False):
    return request('/rest/v1/rpc/apply_operation', {
        'p_operation_id': operation or str(uuid.uuid4()), 'p_kind': kind, 'p_id': rid,
        'p_expected': version, 'p_record': {'id': rid, 'kind': kind, 'data': data, 'deleted': deleted}
    }, token=token)

def product():
    return {'name': 'Яйцо', 'brand': '', 'unit': 'gram', 'nutrition': {'kcal': 155, 'protein': 13, 'fat': 11, 'carbs': 1.1},
            'portions': [{'id': str(uuid.uuid4()), 'name': 'Штука', 'amount': 55}], 'active': True}

def entry():
    return {'day': '2026-10-11', 'meal': 'breakfast', 'name': 'Быстрые КБЖУ', 'nutrition': {'kcal': 100, 'protein': None, 'fat': None, 'carbs': None}, 'amount': 1, 'unit': 'quick'}

class ServerTests(unittest.TestCase):
    def test_activities_private_validation_idempotency(self):
        rid = str(uuid.uuid4())
        data = {'day': '2026-10-12', 'name': 'Walking', 'minutes': 30, 'kcal': 92}
        op = str(uuid.uuid4())
        status, first = rpc(self.ta, 'activity', rid, data, operation=op)
        self.assertEqual(status, 200)
        self.assertEqual(rpc(self.ta, 'activity', rid, data, operation=op), (status, first))
        status, foreign = request('/rest/v1/private_records?id=eq.' + rid, token=self.tb)
        self.assertEqual(status, 200)
        self.assertEqual(foreign, [])
        self.assertEqual(rpc(self.ta, 'activity', str(uuid.uuid4()), {**data, 'minutes': -1})[0], 400)

    @classmethod
    def setUpClass(cls):
        cls.a, cls.ta = user('server-a@example.com')
        cls.b, cls.tb = user('server-b@example.com')
    def test_shared_catalog(self):
        rid = str(uuid.uuid4())
        status, result = rpc(self.ta, 'product', rid, product())
        self.assertEqual(status, 200)
        status, found = request('/rest/v1/products?id=eq.' + rid, token=self.tb)
        self.assertEqual(status, 200)
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0]['version'], 1)
    def test_private_diary_isolation(self):
        rid = str(uuid.uuid4())
        self.assertEqual(rpc(self.ta, 'entry', rid, entry())[0], 200)
        status, found = request('/rest/v1/private_records?id=eq.' + rid, token=self.tb)
        self.assertEqual(status, 200)
        self.assertEqual(found, [])
        self.assertEqual(len(request('/rest/v1/private_records?id=eq.' + rid, token=self.ta)[1]), 1)
    def test_owner_forgery_ignored(self):
        rid = str(uuid.uuid4())
        data = entry() | {'owner_id': self.b}
        self.assertEqual(rpc(self.ta, 'entry', rid, data)[0], 200)
        found = request('/rest/v1/private_records?id=eq.' + rid, token=self.ta)[1][0]
        self.assertEqual(found['owner_id'], self.a)
        self.assertNotIn('owner_id', found['data'])
    def test_direct_catalog_write_denied(self):
        self.assertEqual(request('/rest/v1/products', {'id': str(uuid.uuid4()), 'data': product(), 'version': 1, 'created_by': self.a}, token=self.ta)[0], 403)
    def test_direct_diary_write_denied(self):
        self.assertEqual(request('/rest/v1/private_records', {'owner_id': self.b, 'kind': 'entry', 'id': str(uuid.uuid4()), 'data': entry(), 'version': 1}, token=self.ta)[0], 403)
    def test_audit_forgery_denied(self):
        self.assertEqual(request('/rest/v1/product_versions', {'product_id': str(uuid.uuid4()), 'version': 1, 'actor_id': self.b, 'record': {}}, token=self.ta)[0], 403)
    def test_anonymous_access_denied(self):
        self.assertIn(request('/rest/v1/products')[0], (401, 403))
        self.assertIn(rpc(None, 'product', str(uuid.uuid4()), product())[0], (401, 403))
    def test_public_registration_disabled(self):
        status, _ = request('/auth/v1/signup', {'email': 'not-invited@example.com', 'password': password})
        self.assertIn(status, (400, 403, 422))
    def test_idempotency(self):
        rid, operation, data = str(uuid.uuid4()), str(uuid.uuid4()), product()
        first = rpc(self.ta, 'product', rid, data, operation=operation)
        second = rpc(self.ta, 'product', rid, data, operation=operation)
        self.assertEqual(first, second)
        self.assertEqual(len(request('/rest/v1/product_versions?product_id=eq.' + rid, token=self.ta)[1]), 1)
    def test_idempotency_payload_mismatch(self):
        rid, operation, data = str(uuid.uuid4()), str(uuid.uuid4()), product()
        self.assertEqual(rpc(self.ta, 'product', rid, data, operation=operation)[0], 200)
        self.assertEqual(rpc(self.ta, 'product', rid, data | {'name': 'Подмена'}, operation=operation)[0], 400)
    def test_concurrent_version_control(self):
        rid, data = str(uuid.uuid4()), product()
        self.assertEqual(rpc(self.ta, 'product', rid, data)[0], 200)
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda args: rpc(args[0], 'product', rid, data | {'name': args[1]}, 1), [(self.ta, 'Правка A'), (self.tb, 'Правка B')]))
        self.assertEqual(sorted(r[1]['status'] for r in results), ['applied', 'conflict'])
        self.assertEqual(request('/rest/v1/products?id=eq.' + rid, token=self.ta)[1][0]['version'], 2)
    def test_restore_creates_new_audit_version(self):
        rid, data = str(uuid.uuid4()), product()
        self.assertEqual(rpc(self.ta, 'product', rid, data)[0], 200)
        self.assertEqual(rpc(self.tb, 'product', rid, data | {'name': 'Другое'}, 1)[0], 200)
        self.assertEqual(rpc(self.ta, 'product', rid, data, 2)[0], 200)
        history = request('/rest/v1/product_versions?product_id=eq.' + rid + '&order=version', token=self.ta)[1]
        self.assertEqual(len(history), 3)
        self.assertEqual(history[1]['actor_id'], self.b)
        self.assertEqual(history[2]['previous_record']['data']['name'], 'Другое')
    def test_creator_is_server_owned(self):
        rid = str(uuid.uuid4())
        result = rpc(self.ta, 'product', rid, product() | {'created_by': self.b, 'created_at': '1900-01-01'})[1]
        self.assertEqual(result['record']['data']['created_by'], self.a)
        self.assertFalse(result['record']['data']['created_at'].startswith('1900'))
    def test_soft_delete_restore(self):
        rid, data = str(uuid.uuid4()), product()
        rpc(self.ta, 'product', rid, data)
        self.assertTrue(rpc(self.ta, 'product', rid, data, 1, deleted=True)[1]['record']['deleted'])
        self.assertFalse(rpc(self.ta, 'product', rid, data, 2)[1]['record']['deleted'])
    def test_invalid_nutrition_rejected(self):
        data = product()
        data['nutrition']['protein'] = -1
        self.assertEqual(rpc(self.ta, 'product', str(uuid.uuid4()), data)[0], 400)
    def test_pull_filters_private_data(self):
        rid = str(uuid.uuid4())
        rpc(self.ta, 'entry', rid, entry())
        status, result = request('/rest/v1/rpc/pull_changes', {'p_cursor': 0, 'p_limit': 500}, token=self.tb)
        self.assertEqual(status, 200)
        self.assertFalse(any(r['id'] == rid for r in result['records']))
    def test_pagination_cursor(self):
        cursor, seen = 0, []
        while True:
            status, page = request('/rest/v1/rpc/pull_changes', {'p_cursor': cursor, 'p_limit': 2}, token=self.ta)
            self.assertEqual(status, 200)
            self.assertGreaterEqual(page['cursor'], cursor)
            seen.extend((r['id'], r['version']) for r in page['records'])
            if not page['has_more']:
                break
            self.assertGreater(page['cursor'], cursor)
            cursor = page['cursor']
        self.assertEqual(len(seen), len(set(seen)))

if '--android-fixtures' in sys.argv:
    user('android-a@example.com')
    user('android-b@example.com')
    with open(os.environ['GITHUB_ENV'], 'a') as target:
        target.write('TEST_ANON_KEY=' + anon + '\n')
else:
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(ServerTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    sys.exit(not result.wasSuccessful())
