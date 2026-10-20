# Mobile screenshots (every role, real Android emulator)

Real screenshots of the EduX app on Android (API 34, Pixel 6, 1080x2400) for every demo role:
director, admin, cashier, marketer, teacher, student, guardian and the platform owner.
GitHub Actions cannot reach a local backend, so the run works on **recorded fixtures**:

```
local demo backend ──record.py──▶ tool/shots/fixtures/<role>/*.json ──(git push shots)──▶ CI
CI: server.py (0.0.0.0:8000) ◀── app on emulator (http://10.0.2.2:8000) ── integration_test/shots_test.dart
                         └── POST /__shot/<name> → adb exec-out screencap -p → shots/<name>.png
```

| File | What it does |
| --- | --- |
| `record.py` | Logs in as each role against the demo backend and saves the real JSON of every endpoint the screens call (lists, details of the first items, query variants). Absolute server URLs become `__SERVER__`. |
| `server.py` | Stdlib-only fixture server: `auth/login` by phone → token `shots-<role>`; GETs served by token + path + query (closest recorded query when dates differ); other writes → `200 {}`; unknown GETs → 404 and a `MISS` line in the log. Also takes screenshots (`/__shot/<name>`) and test log lines (`/__log`). |
| `run_on_emulator.sh` | Runs inside the emulator: clean status bar (demo mode, 09:41), then `flutter test integration_test/shots_test.dart`. |
| `../../integration_test/shots_test.dart` | Starts the app like `lib/main.dart` (Uzbek, light theme), logs in through the real login form, opens every tab and the key pages of the role, waits until skeletons/spinners are gone, asks the server for a screenshot. Nothing in `lib/` is changed. |
| `../../.github/workflows/shots.yml` | CI on push to `shots` / manual run: Flutter + `flutter create` (as in build.yml), cleartext HTTP allowed for this debug run, KVM, fixture server, `reactivecircus/android-emulator-runner`. Artifact: **mobile-screenshots** (PNGs + `server.log` + `test.log`). |

File names: `<NN-role>-<NN>-<screen>.png`, e.g. `01-director-05-more.png`, `06-student-12-olympiads.png`.

## Re-record fixtures

1. Start the demo backend (DB `edux_shot`, password `password` for all demo users):

   ```bash
   cd /home/claude/work/edux && DB_PORT=3307 DB_DATABASE=edux_shot php artisan serve --port=8090
   ```

2. Record (overwrites `tool/shots/fixtures/`):

   ```bash
   python3 tool/shots/record.py --base http://127.0.0.1:8090
   # only some roles:  --roles director,student
   ```

   Demo logins are in `ROLES` (record.py) and `roles` (shots_test.dart) — keep them in sync.
   Olympiad tokens shown to the student: `SHOTS_OLYMPIADS=tok1,tok2` (record.py) and `tokens` in `studentFlow`.

3. Optional local check of the server:

   ```bash
   python3 tool/shots/server.py --port 8000 --shots /tmp/shots &
   curl -s -X POST localhost:8000/api/v1/auth/login -d '{"login":"+998900000005","password":"password"}'
   curl -s localhost:8000/api/v1/my/exams -H 'Authorization: Bearer shots-student'
   ```

## Run

* Push to branch `shots` (or *Actions → Shots → Run workflow*). ~25–35 min.
* Watch: `gh run list --repo Azamat4588/edux-mobile --branch shots --limit 3`
* Download: `bash tool/shots/fetch.sh <run id> <out dir>` — takes the zip from the run's draft release
  `shots-<run id>` (the workflow keeps only the newest one; drafts have no tag and are not public) or, if missing,
  from the Actions artifact **mobile-screenshots**.

* In the job log («Natija» step) and in `server.log`: `MISS` = endpoint without a fixture (add it to record.py),
  `NEAR` = served from the closest recorded query, `TEST <file> [ERROR-STATE|empty-state|still-loading] :: texts`
  = what each screenshot shows, `SHOTS FLUTTER ERROR` (test.log) = layout overflows and other Flutter errors.

With a local Android emulator/device the same test runs without CI:

```bash
python3 tool/shots/server.py --port 8000 --shots shots &
flutter test integration_test/shots_test.dart --dart-define=EDUX_SERVER=http://10.0.2.2:8000
```

(For a real phone use the computer's LAN address; the app needs `android:usesCleartextTraffic="true"` for plain HTTP —
the workflow adds it to the generated manifest.)
