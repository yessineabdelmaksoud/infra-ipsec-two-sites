# 03 — Phase 3: web server + MySQL

**Goal (from the spec):** install Nginx (or Apache2) and MySQL on two separate VMs,
create a database and a user allowed from the web server. **Test:** the web page
displays data loaded from MySQL.

**Status:** ✅ done — Site A and Site B (lab mode) pass `make test-phase3`.

## The picture

```text
   your computer (.254)          a-web 10.0.2.7                    a-db 10.0.2.8
   browser / curl  ───HTTP──▶  Nginx ──▶ PHP-FPM ──SQL (TCP 3306)──▶ MySQL 8.0
                               index.php                           database "infra"
                               /health  /whoami                    user app@10.0.2.7 only
```

- **Nginx** receives HTTP. For `index.php` it asks **PHP-FPM** (the PHP program
  runner) to execute the page.
- The page connects to **MySQL on another VM** (`10.0.2.8`) with the user `app`.
- MySQL accepts `app` **only when it comes from `10.0.2.7`**. From any other
  machine the login is refused — even with the right password.

## Run it

```bash
make phase3 SITE=a          # ~3 minutes the first time (package downloads)
make test-phase3 SITE=a
```

Open `http://10.0.2.7/` in a browser on this computer: you see the site header
(blue for Site A, green for Site B), three messages **read from MySQL**, and a
page-view counter that goes up at every refresh (it is an `UPDATE` in MySQL —
proof that the data is live, not a static file).

---

## How the code works

The playbook [playbooks/phase3.yml](../playbooks/phase3.yml) runs three roles:

| Role | On | Does |
|---|---|---|
| [base](../roles/base/tasks/main.yml) | all 4 VMs | switches off Ubuntu's automatic updates (see "Problems we hit") |
| [mysql](../roles/mysql/tasks/main.yml) | `db` | installs MySQL, listens on the LAN address, creates DB + table + user |
| [webapp](../roles/webapp/tasks/main.yml) | `web` | installs Nginx + PHP, deploys the page and the DB settings |

### 1. MySQL listens on the LAN only

By default MySQL listens on `127.0.0.1` (only itself). We add one small file,
[zz-infra.cnf.j2](../roles/mysql/templates/zz-infra.cnf.j2):

```ini
[mysqld]
bind-address        = 10.0.2.8     # the LAN address: the web VM can reach it
mysqlx-bind-address = 127.0.0.1    # the "X protocol" port 33060 stays local
```

The name starts with `zz-` so it is read **after** Ubuntu's own `mysqld.cnf` and wins.

### 2. The database, in plain SQL

[app.sql.j2](../roles/mysql/templates/app.sql.j2), rendered for Site A:

```sql
CREATE DATABASE IF NOT EXISTS infra CHARACTER SET utf8mb4;
CREATE TABLE IF NOT EXISTS messages (id INT PRIMARY KEY, message VARCHAR(255) NOT NULL, ...);
INSERT INTO messages (id, message) VALUES (1, 'Welcome to Site A: ...'), ...
  ON DUPLICATE KEY UPDATE message = VALUES(message);      -- run twice = no duplicates

CREATE USER IF NOT EXISTS 'app'@'10.0.2.7' IDENTIFIED BY '...';
GRANT SELECT ON infra.messages TO 'app'@'10.0.2.7';
GRANT SELECT, UPDATE ON infra.page_views TO 'app'@'10.0.2.7';
```

- `'app'@'10.0.2.7'` — in MySQL a user is **name + the host it comes from**.
  This is how "the user is permitted from the web server" (spec) is enforced.
- **Least privilege:** `app` can only read messages and update the counter. It
  cannot drop tables or create users.
- `IF NOT EXISTS` / `ON DUPLICATE KEY` make the script **idempotent**: Ansible
  can run it again safely. It is only re-run when its content changes.
- Ansible runs it as MySQL `root` through the local socket. On Ubuntu, root uses
  `auth_socket` (= "you are Linux root, so you are MySQL root"): no root password exists to leak.

> We wrote plain SQL instead of using Ansible's `community.mysql` modules: they
> are not included in our pinned Ansible bundle, and plain SQL is easier to read
> and to explain at the defense.

### 3. Where the password lives

```yaml
# inventories/common/group_vars/all.yml
app_db_password: "{{ lookup('ansible.builtin.password', secrets_dir ~ '/mysql-app-' ~ site_id, ...) }}"
```

The first run generates a random password into `.secrets/mysql-app-a`
(git-ignored). Every later run reads the same file. On the web VM it is written
to `/etc/infra-app/config.php` — **outside the web root**, readable only by
`root` and the PHP user `www-data` (mode `0640`).

```bash
cat .secrets/mysql-app-a     # the password to type for acceptance test 3
```

### 4. The page

[roles/webapp/files/index.php](../roles/webapp/files/index.php) does:

```php
$db = new mysqli($cfg['db_host'], $cfg['db_user'], $cfg['db_pass'], $cfg['db_name']);
$db->query('UPDATE page_views SET total = total + 1 WHERE id = 1');
$messages = $db->query('SELECT id, message, created_at FROM messages ORDER BY id')->fetch_all(MYSQLI_ASSOC);
```

and prints them in an HTML table, plus a **"How this request travelled"** box:
your address, which **HAProxy node** forwarded the request (Phase 4), the web
server, the database. Every value is escaped with `htmlspecialchars` (no HTML
injection). If MySQL is down, the page shows the error and returns HTTP 503.

### 5. Two tiny endpoints for later phases

From [nginx-site.conf.j2](../roles/webapp/templates/nginx-site.conf.j2):

```nginx
location = /health { return 200 "OK\n"; }            # HAProxy health check (Phase 4)
location = /whoami { return 200 "$remote_addr\n"; }  # who is calling me? (Phase 6: proves no NAT)
```

### 6. The test

[tests/phase3.yml](../tests/phase3.yml):

| Check | How |
|---|---|
| MySQL listens on `10.0.2.8:3306`, not `0.0.0.0` | `ss -ltn` on a-db |
| **Acceptance test 3**: `app` logs in from the web VM | `mysql -h 10.0.2.8 -u app infra -e 'SELECT COUNT(*) FROM messages'` on a-web |
| `app` is refused from another VM | from a-haproxy1, MySQL answers *"Host '10.0.2.5' is not allowed to connect"* |
| The page shows MySQL data | `GET http://10.0.2.7/` contains *"stored in MySQL on a-db"* |

---

## Check by hand (good for the report)

```bash
ssh -i .secrets/infra_ed25519 infra@10.0.2.7         # log into a-web
mysql -h 10.0.2.8 -u app -p                          # password: .secrets/mysql-app-a
mysql> USE infra;
mysql> SELECT * FROM messages;
mysql> SELECT * FROM page_views;
mysql> exit
curl -s http://10.0.2.7/whoami                        # 10.0.2.7 (it called itself)
exit

ssh -i .secrets/infra_ed25519 infra@10.0.2.5         # a-haproxy1 (no MySQL client installed here)
nc -v 10.0.2.8 3306                                   # "...Host '10.0.2.5' is not allowed to connect..."
```

## Problems we hit

| Problem | Cause | Fix |
|---|---|---|
| `apt` failed: *Could not get lock /var/lib/dpkg/lock-frontend* | As soon as OPNsense gave the VMs Internet, Ubuntu's **unattended-upgrades** started updating in the background and held the package lock | role `base`: stop the daily apt timers and remove `unattended-upgrades` (waiting up to 15 min for a running update). On lab VMs only Ansible installs packages |
| The page still showed *"Welcome to nginx!"* although the config was right and the reload "succeeded" | Our site said `listen 10.0.2.7:80`; the old default site was bound on `0.0.0.0:80`. During a **reload**, nginx could not bind the specific address next to the wildcard one, logged `bind() ... Address already in use` in `/var/log/nginx/error.log` and **kept the old config** | `listen 80` (the VM has a single address anyway). Lesson: after a reload, check the error log, not only the exit code |
