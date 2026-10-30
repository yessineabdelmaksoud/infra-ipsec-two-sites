<?php
// Managed by Ansible (roles/webapp). Shows data read from MySQL plus the path
// the request took, so the demo can show which HAProxy node answered.
$cfg = require '/etc/infra-app/config.php';

function h($s) { return htmlspecialchars((string) $s, ENT_QUOTES, 'UTF-8'); }

$error = null;
$messages = [];
$views = null;
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
try {
    $db = new mysqli($cfg['db_host'], $cfg['db_user'], $cfg['db_pass'], $cfg['db_name']);
    $db->query('UPDATE page_views SET total = total + 1 WHERE id = 1');
    $views = $db->query('SELECT total FROM page_views WHERE id = 1')->fetch_row()[0];
    $messages = $db->query('SELECT id, message, created_at FROM messages ORDER BY id')->fetch_all(MYSQLI_ASSOC);
    $db_version = $db->server_info;
    $db->close();
} catch (mysqli_sql_exception $e) {
    $error = $e->getMessage();
    http_response_code(503);
}

$proxy  = $_SERVER['HTTP_X_PROXY_NODE'] ?? 'direct (no proxy)';
$client = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['REMOTE_ADDR'];
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= h($cfg['site_name']) ?> — Infrastructure IT</title>
<style>
  body { font-family: system-ui, sans-serif; margin: 0; background: #f4f6f8; color: #1c2430; }
  header { background: <?= h($cfg['color']) ?>; color: #fff; padding: 24px 32px; }
  header h1 { margin: 0 0 4px; font-size: 28px; }
  main { max-width: 860px; margin: 24px auto; padding: 0 16px; }
  .card { background: #fff; border-radius: 8px; padding: 16px 20px; margin-bottom: 16px; box-shadow: 0 1px 3px rgba(0,0,0,.08); }
  table { border-collapse: collapse; width: 100%; }
  td, th { text-align: left; padding: 6px 8px; border-bottom: 1px solid #e3e7ec; vertical-align: top; }
  th { width: 34%; color: #4a5565; font-weight: 600; }
  .error { background: #fde8e8; color: #8a1c1c; }
  code { font-size: 14px; }
</style>
</head>
<body>
<header>
  <h1><?= h($cfg['site_name']) ?></h1>
  <div>IPsec site-to-site project · OPNsense · HAProxy + Keepalived · Nginx · MySQL</div>
</header>
<main>
<?php if ($error !== null): ?>
  <div class="card error"><strong>Database error:</strong> <?= h($error) ?></div>
<?php else: ?>
  <div class="card">
    <h2>Data from MySQL</h2>
    <table>
      <tr><th>#</th><th>Message</th></tr>
<?php foreach ($messages as $m): ?>
      <tr><td><?= h($m['id']) ?></td><td><?= h($m['message']) ?></td></tr>
<?php endforeach; ?>
    </table>
    <p>Page views stored in the database: <strong id="views"><?= h($views) ?></strong></p>
  </div>
<?php endif; ?>
  <div class="card">
    <h2>How this request travelled</h2>
    <table>
      <tr><th>Your address</th><td><code><?= h($client) ?></code></td></tr>
      <tr><th>HAProxy node</th><td><code id="proxy"><?= h($proxy) ?></code></td></tr>
      <tr><th>Web server</th><td><code id="web"><?= h(gethostname()) ?> (<?= h($_SERVER['SERVER_ADDR'] ?? '') ?>)</code></td></tr>
      <tr><th>Database</th><td><code id="db"><?= h($cfg['db_host']) ?><?= isset($db_version) ? ' · MySQL ' . h($db_version) : '' ?></code></td></tr>
      <tr><th>Time</th><td><code><?= h(date('Y-m-d H:i:s T')) ?></code></td></tr>
    </table>
  </div>
</main>
</body>
</html>
