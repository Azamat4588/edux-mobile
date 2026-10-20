#!/usr/bin/env python3
"""Record real API responses of the local EduX demo backend as fixtures for the screenshot run.

    python3 tool/shots/record.py [--base http://127.0.0.1:8090] [--out tool/shots/fixtures]

For each demo role it logs in (POST auth/login), then GETs every endpoint the mobile screens call
(see lib/**: api.get(...)) including the detail pages of the first list items, and stores
fixtures/<role>/<key>.json = {method, path, query, status, body}. Public endpoints (site, auth/options)
go to fixtures/_public/. Absolute URLs of the recording server are replaced with "__SERVER__";
tool/shots/server.py puts its own address back. Python stdlib only.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import sys
import urllib.error
import urllib.parse
import urllib.request

ROLES = {
    # role: (login phone, kind)
    'director': ('+998900000001', 'staff'),
    'admin': ('+998901110001', 'staff'),
    'cashier': ('+998901110004', 'staff'),
    'marketer': ('+998901110005', 'staff'),
    'teacher': ('+998901110002', 'staff'),
    'student': ('+998900000005', 'student'),
    'guardian': ('+998900000009', 'guardian'),
    'owner': ('+998900000000', 'owner'),
}
PASSWORD = 'password'


def canonical(path, query):
    path = path.strip('/')
    items = sorted((k, str(v)) for k, v in (query or {}).items() if v is not None and str(v) != '')
    return path + ('?' + urllib.parse.urlencode(items) if items else '')


def file_name(method, key):
    safe = re.sub(r'[^A-Za-z0-9._-]+', '_', key).strip('_')[:90]
    digest = hashlib.sha1(f'{method} {key}'.encode()).hexdigest()[:8]
    return f'{method}_{safe}_{digest}.json'


class Recorder:
    def __init__(self, base, out):
        self.base = base.rstrip('/')
        self.api = self.base + '/api/v1/'
        self.out = out
        self.token = None
        self.dir = None
        self.count = 0
        self.servers = [self.base, self.base.replace('127.0.0.1', 'localhost'), 'http://localhost']

    def scrub(self, text):
        for server in self.servers:
            text = text.replace(server, '__SERVER__').replace(server.replace('/', '\\/'), '__SERVER__')
        return text

    def request(self, method, path, query=None, body=None):
        url = self.api + path.strip('/')
        params = {k: v for k, v in (query or {}).items() if v is not None and str(v) != ''}
        if params:
            url += '?' + urllib.parse.urlencode(params)
        headers = {'Accept': 'application/json', 'X-Locale': 'uz', 'X-Requested-With': 'EduXMobile'}
        data = None
        if body is not None:
            data = json.dumps(body).encode()
            headers['Content-Type'] = 'application/json'
        if self.token:
            headers['Authorization'] = 'Bearer ' + self.token
            headers['X-Organization'] = '1'
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                status, raw = resp.status, resp.read()
        except urllib.error.HTTPError as error:
            status, raw = error.code, error.read()
        text = raw.decode('utf-8', 'replace')
        try:
            parsed = json.loads(self.scrub(text)) if text.strip() else None
        except ValueError:
            parsed = {'message': 'non-json response'}
            status = status if status >= 400 else 500
        return status, parsed

    def get(self, path, query=None, save=True, method='GET', body=None):
        status, body = self.request(method, path, query, body)
        if save:
            key = canonical(path, query)
            record = {'method': method, 'path': path.strip('/'), 'query': {k: str(v) for k, v in (query or {}).items() if v not in (None, '')},
                      'status': status, 'body': body}
            with open(os.path.join(self.dir, file_name(method, key)), 'w', encoding='utf-8') as fh:
                json.dump(record, fh, ensure_ascii=False, indent=1)
            self.count += 1
            flag = '' if status < 400 else '   <-- %d' % status
            print(f'  {method} {key}{flag}')
        return status, body


def items(body, key='data'):
    if isinstance(body, list):
        return [x for x in body if isinstance(x, dict)]
    if isinstance(body, dict) and isinstance(body.get(key), list):
        return [x for x in body[key] if isinstance(x, dict)]
    return []


def ids(body, key='data', limit=3, field='id'):
    return [x[field] for x in items(body, key)[:limit] if x.get(field) is not None]


def record_staff(r, role, today, month_start):
    r.get('overview')
    r.get('crm/timetable', {'from': today, 'to': today})
    r.get('crm/timetable', {'date': today})
    r.get('crm/groups', {'active': 1})
    s, groups = r.get('crm/groups')
    for gid in ids(groups, limit=4):
        r.get('crm/attendance', {'group_id': gid, 'date': today})
    s, exams = r.get('exams')
    r.get('exams', {'status': 'published'})
    for eid in ids(exams, limit=8):
        r.get(f'exams/{eid}/results')
        r.get(f'exams/{eid}')
    for status in ('needs_review', None, 'confirmed', 'rejected'):
        s, scans = r.get('scans', {'status': status})
        for sid in ids(scans, limit=2):
            r.get(f'scans/{sid}')
    s, crm_students = r.get('crm/students')
    r.get('crm/students', {'page': 1})
    s, plain_students = r.get('students')
    r.get('students', {'page': 1})
    s, mine = r.get('students', {'page': 1, 'mine': 1})
    if not ids(crm_students):
        crm_students = mine if ids(mine) else plain_students
    for sid in ids(crm_students, limit=6):
        r.get(f'crm/students/{sid}')
        r.get(f'students/{sid}/insights')
    for status in ('new', 'contacted', 'trial', 'won', 'lost', None):
        s, leads = r.get('crm/leads', {'status': status, 'archived': 0})
        for lid in ids(leads, limit=3):
            r.get(f'crm/leads/{lid}')
    r.get('crm/lookups')
    for tab in ('today', 'overdue', 'upcoming', 'done'):
        r.get('crm/tasks', {'tab': tab})
    r.get('crm/payments', {'from': today, 'to': today, 'page': 1})
    r.get('crm/payments', {'from': month_start, 'to': today, 'page': 1})
    r.get('crm/payments', {'page': 1})
    r.get('crm/cash', {'from': today, 'to': today})
    r.get('crm/debtors', {'page': 1})
    r.get('crm/reports/summary', {'from': month_start, 'to': today})
    r.get('crm/reports/monthly')
    base = 'crm/callcenter'
    r.get(f'{base}/live')
    r.get(f'{base}/queue')
    r.get(f'{base}/scripts')
    for direction in (None, 'in', 'out'):
        r.get(f'{base}/calls', {'from': today, 'to': today, 'page': 1, 'direction': direction})
        r.get(f'{base}/calls', {'page': 1, 'direction': direction})
    s, calls = r.get(f'{base}/calls', {'page': 1})
    for call in items(calls)[:3]:
        if call.get('phone'):
            r.get(f'{base}/caller', {'phone': call['phone']})
    s, topics = r.get('bank/topics')
    for subj in items(topics, 'subjects')[:6]:
        code = subj.get('code')
        if code:
            r.get('bank/topics', {'subject': code})
    tree = (topics or {}).get('tree') if isinstance(topics, dict) else None
    if isinstance(tree, dict):
        for section in (tree.get('sections') or [])[:2]:
            for topic in (section.get('topics') or [])[:2]:
                r.get(f"bank/topics/{topic.get('code')}/questions", {'language': tree.get('language')})
    record_billing(r)
    record_common_tail(r, role)


def record_billing(r):
    """GET billing and the first POST billing/quote the page sends (same initial selection as billing_page.dart)."""
    status, data = r.get('billing')
    if status >= 400 or not isinstance(data, dict):
        return
    available = [str(m.get('module')) for m in items(data, 'available_modules')]
    plan = [m for m in (data.get('plan_modules') or []) if m in available]
    paid = [m for m in (data.get('paid_modules') or []) if m in available]
    modules = plan or paid or available[:1]
    cycles = data.get('cycles') or {}
    cycle = data.get('cycle') if isinstance(cycles, dict) and data.get('cycle') in cycles else 'monthly'
    plans = items(data, 'plans')
    if data.get('pricing_mode') != 'modules' and plans:
        current = str(data.get('plan_code') or '')
        featured = next((p for p in plans if p.get('featured') is True), plans[0])
        code = current if current and any(str(p.get('code')) == current for p in plans) else str(featured.get('code'))
        plan_addons = {str(a.get('code')) for p in plans if str(p.get('code')) == code for a in (p.get('addons') or []) if isinstance(a, dict)}
        paid_addons = {str(a.get('addon')) for a in items(data, 'addon_states') if a.get('mode') == 'paid' and str(a.get('addon')) not in plan_addons}
        body = {'plan_code': code, 'addons': [a for a in (data.get('bought_addons') or []) if a in paid_addons], 'cycle': cycle}
    else:
        paid_addons = {str(a.get('addon')) for a in items(data, 'addon_states') if a.get('mode') == 'paid'}
        body = {'modules': modules, 'addons': [a for a in (data.get('bought_addons') or []) if a in paid_addons], 'cycle': cycle}
    r.get('billing/quote', method='POST', body=body)


def record_common_tail(r, role):
    s, support = r.get('my/support')
    r.get('public/support')
    for ticket in items(support, 'data')[:2] + items(support, 'tickets')[:2]:
        if ticket.get('token'):
            r.get(f"public/support/{ticket['token']}")
    r.get('ai/status')
    for kind in ('staff', 'tutor'):
        s, convs = r.get('ai/conversations', {'kind': kind})
        for cid in ids(convs, limit=2):
            r.get(f'ai/conversations/{cid}')
    r.get('pay/options')


def record_student(r, role):
    s, insights = r.get('my/insights')
    r.get('crm/me')
    s, exams = r.get('my/exams')
    for exam in items(exams, 'exams'):
        attempt = exam.get('attempt') or {}
        if attempt.get('id'):
            r.get(f"attempts/{attempt['id']}")
    for attempt in ((insights or {}).get('testing') or {}).get('attempts', [])[:6] if isinstance(insights, dict) else []:
        if attempt.get('id'):
            r.get(f"attempts/{attempt['id']}")
    s, courses = r.get('lms/my/courses')
    for course in items(courses, 'courses')[:3]:
        s, detail = r.get(f"lms/my/courses/{course['id']}")
        lessons = []
        if isinstance(detail, dict):
            for module in (detail.get('sections') or []) + (detail.get('modules') or []):
                lessons += module.get('lessons') or []
            lessons += detail.get('lessons') or []
        for lesson in lessons[:5]:
            if isinstance(lesson, dict) and lesson.get('id'):
                r.get(f"lms/my/lessons/{lesson['id']}")
    s, certs = r.get('my/certificates')
    for cert in items(certs):
        if cert.get('attempt_id'):
            r.get(f"attempts/{cert['attempt_id']}")
    r.get('my/mock')
    r.get('lms/my/assignments')
    r.get('my/games')
    r.get('my/achievements')
    r.get('my/labs')
    r.get('school/my/diary')
    for token in olympiad_tokens():
        r.get(f'public/olympiads/{token}')
    record_common_tail(r, role)


def record_guardian(r, role, today):
    s, insights = r.get('my/insights')
    children = items(insights, 'children') if isinstance(insights, dict) else []
    child_ids = [c['id'] for c in children if c.get('id')]
    if not child_ids and isinstance(insights, dict) and isinstance(insights.get('student'), dict):
        child_ids = [insights['student']['id']]
    r.get('crm/my/children')
    r.get('my/children')
    r.get('school/my/students')
    for cid in child_ids:
        r.get('my/insights', {'student_id': cid})
        r.get('school/my/progress', {'student_id': cid})
        r.get('school/my/diary', {'student_id': cid})
        r.get('school/my/diary', {'student_id': cid, 'date': today})
    s, kids = r.get('my/children')
    for kid in items(kids, 'children'):
        for attempt in kid.get('attempts') or []:
            if attempt.get('id'):
                r.get(f"attempts/{attempt['id']}")
    record_common_tail(r, role)


def olympiad_tokens():
    return [t for t in os.environ.get('SHOTS_OLYMPIADS', 'qpawfft3s432,sklssskru2zd,0khb5onxpi7z').split(',') if t]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--base', default='http://127.0.0.1:8090')
    parser.add_argument('--out', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fixtures'))
    parser.add_argument('--roles', default=','.join(ROLES))
    args = parser.parse_args()
    today = dt.date.today()
    today_s, month_start = today.isoformat(), today.replace(day=1).isoformat()

    r = Recorder(args.base, args.out)
    os.makedirs(args.out, exist_ok=True)
    public = os.path.join(args.out, '_public')
    shutil.rmtree(public, ignore_errors=True)
    os.makedirs(public)
    r.dir = public
    print('[_public]')
    r.get('site')
    r.get('auth/options')

    logins = {}
    for role in args.roles.split(','):
        phone, kind = ROLES[role]
        print(f'[{role}] {phone}')
        r.token = None
        status, data = r.request('POST', 'auth/login', body={'login': phone, 'password': PASSWORD, 'device_name': 'EduX mobil'})
        if status != 200 or not isinstance(data, dict) or not data.get('token'):
            print(f'  login failed: {status} {data}', file=sys.stderr)
            sys.exit(1)
        r.token = data['token']
        folder = os.path.join(args.out, role)
        shutil.rmtree(folder, ignore_errors=True)
        os.makedirs(folder)
        r.dir = folder
        login = dict(data)
        login['token'] = f'shots-{role}'
        logins[phone] = {'role': role, 'response': login}
        r.get('me')
        if kind != 'owner':
            r.get('context')
        if kind == 'staff':
            record_staff(r, role, today_s, month_start)
        elif kind == 'student':
            record_student(r, role)
        elif kind == 'guardian':
            record_guardian(r, role, today_s)
        r.request('POST', 'auth/logout')
        r.token = None
    with open(os.path.join(args.out, 'logins.json'), 'w', encoding='utf-8') as fh:
        json.dump({'recorded_at': dt.datetime.now().isoformat(timespec='seconds'), 'password': PASSWORD, 'logins': logins},
                  fh, ensure_ascii=False, indent=1)
    print(f'{r.count} fixtures -> {args.out}')


if __name__ == '__main__':
    main()
