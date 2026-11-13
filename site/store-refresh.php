<?php
/**
 * Knop "Nieuwe apps ophalen" in beheer.html.
 *   POST ?mode=...  start de GitHub-workflow "Store-check" (toevoegen: met &url=<link>):
 *                   nieuw = alleen nieuwe apps zoeken en beta-apps aanvullen, bijwerken = alleen bestaande apps bijwerken
 *   GET ?since=...  geeft de voortgang. Is de run klaar, dan worden apps.json en nieuwe iconen meteen
 *                   van GitHub op deze server gezet, zodat ze direct zichtbaar zijn.
 *
 * Beveiligd met dezelfde login als beheer.html (zie .htaccess).
 * Gebruikt de GitHub-token uit .publish-config.php; die heeft Contents (lezen en schrijven) en Actions (lezen en schrijven) nodig.
 */

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function reply(int $code, array $body): void {
    http_response_code($code);
    echo json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

if (($_SERVER['HTTP_X_LR_BEHEER'] ?? '') !== '1') {
    reply(403, ['ok' => false, 'error' => 'Ontbrekende beheer-header.']);
}
$cfgFile = __DIR__ . '/.publish-config.php';
if (!is_file($cfgFile)) {
    reply(500, ['ok' => false, 'error' => 'De GitHub-token ontbreekt op de server (secret PUBLISH_GITHUB_TOKEN).']);
}
$cfg = require $cfgFile;
$workflow = 'store-check.yml';

function gh(string $method, string $url, array $cfg, ?array $body = null, bool $raw = false) {
    $ch = curl_init('https://api.github.com/repos/' . $cfg['repo'] . $url);
    curl_setopt_array($ch, [
        CURLOPT_CUSTOMREQUEST => $method,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 30,
        CURLOPT_HTTPHEADER => [
            'Authorization: Bearer ' . $cfg['token'],
            'Accept: ' . ($raw ? 'application/vnd.github.raw+json' : 'application/vnd.github+json'),
            'X-GitHub-Api-Version: 2022-11-28',
            'User-Agent: lrvdlinden-beheer',
            'Content-Type: application/json',
        ],
    ]);
    if ($body !== null) curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body));
    $res = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($code === 403 || $code === 404) {
        throw new RuntimeException('GitHub weigert de aanvraag (HTTP ' . $code . '). Geef de token PUBLISH_GITHUB_TOKEN ook de permissie "Actions: Read and write" en draai daarna Release site opnieuw.');
    }
    if ($code < 200 || $code >= 300) {
        $d = json_decode((string)$res, true) ?: [];
        throw new RuntimeException('GitHub gaf HTTP ' . $code . ': ' . ($d['message'] ?? 'onbekende fout'));
    }
    return $raw ? (string)$res : (json_decode((string)$res, true) ?: []);
}

try {
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $since = gmdate('Y-m-d\TH:i:s\Z', time() - 5);
        $mode = $_GET['mode'] ?? 'alles';
        if (!in_array($mode, ['alles', 'nieuw', 'bijwerken', 'toevoegen'], true)) $mode = 'alles';
        $inputs = ['mode' => $mode];
        if ($mode === 'toevoegen') {
            // App toevoegen vanaf een link: App Store, Homey App Store, TestFlight of een website
            $url = trim((string)($_GET['url'] ?? ''));
            if ($url === '' || strlen($url) > 500 || preg_match('/[\s<>"\']/', $url)) {
                reply(400, ['ok' => false, 'error' => 'Geef een geldige link of App Store-id.']);
            }
            $inputs['url'] = $url;
            $inputs['nlonly'] = (($_GET['nlonly'] ?? '') === '1') ? 'true' : 'false';
        }
        gh('POST', '/actions/workflows/' . $workflow . '/dispatches', $cfg,
           ['ref' => $cfg['branch'] ?? 'main', 'inputs' => $inputs]);
        reply(200, ['ok' => true, 'since' => $since]);
    }

    $since = $_GET['since'] ?? '';
    if (!preg_match('/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/', $since)) {
        reply(400, ['ok' => false, 'error' => 'Ongeldige starttijd.']);
    }
    $runs = gh('GET', '/actions/workflows/' . $workflow . '/runs?event=workflow_dispatch&per_page=5', $cfg);
    $run = null;
    foreach ($runs['workflow_runs'] ?? [] as $r) {
        if (($r['created_at'] ?? '') >= $since) { $run = $r; break; }
    }
    if (!$run) reply(200, ['ok' => true, 'state' => 'queued']);
    if (($run['status'] ?? '') !== 'completed') reply(200, ['ok' => true, 'state' => 'running', 'url' => $run['html_url']]);
    if (($run['conclusion'] ?? '') !== 'success') {
        reply(200, ['ok' => true, 'state' => 'failed', 'url' => $run['html_url']]);
    }

    // Klaar: nieuwste apps.json en ontbrekende iconen van GitHub direct op de server zetten
    $branch = $cfg['branch'] ?? 'main';
    $json = gh('GET', '/contents/site/apps.json?ref=' . rawurlencode($branch), $cfg, null, true);
    $data = json_decode($json, true);
    if (!is_array($data) || !isset($data['apps'])) {
        reply(200, ['ok' => true, 'state' => 'failed', 'error' => 'apps.json op GitHub is ongeldig.', 'url' => $run['html_url']]);
    }
    $icons = 0;
    foreach ($data['apps'] as $a) {
        foreach ([$a['icon'] ?? null] as $p) {
            if (!is_string($p) || !preg_match('#^img/[a-z0-9-]+\.(webp|png|jpg|svg)$#', $p)) continue;
            if (is_file(__DIR__ . '/' . $p)) continue;
            $bin = gh('GET', '/contents/site/' . $p . '?ref=' . rawurlencode($branch), $cfg, null, true);
            if ($bin !== '' && @file_put_contents(__DIR__ . '/' . $p, $bin) !== false) $icons++;
        }
    }
    $local = @file_get_contents(__DIR__ . '/apps.json');
    $changed = $local !== $json;
    if ($changed && @file_put_contents(__DIR__ . '/apps.json.tmp', $json) !== false) {
        @rename(__DIR__ . '/apps.json.tmp', __DIR__ . '/apps.json');
    }
    reply(200, ['ok' => true, 'state' => 'done', 'changed' => $changed, 'icons' => $icons, 'url' => $run['html_url']]);
} catch (Throwable $e) {
    reply(200, ['ok' => false, 'error' => $e->getMessage()]);
}
