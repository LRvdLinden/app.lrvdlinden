<?php
/**
 * Publiceert wijzigingen uit beheer.html.
 *  1. Schrijft apps.json (en nieuwe iconen) direct naar deze server, zodat ze meteen live zijn.
 *  2. Zet dezelfde bestanden in één commit in de GitHub-repo, zodat een volgende deploy ze niet overschrijft.
 *     Die commit start de workflow, die de site opnieuw via FTP uploadt en een zip-release maakt.
 *
 * Beveiligd met dezelfde gebruikersnaam en hetzelfde wachtwoord als beheer.html (zie .htaccess).
 * De GitHub-token staat in .publish-config.php, die de workflow aanmaakt uit secret PUBLISH_GITHUB_TOKEN.
 */

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function reply(int $code, array $body): void {
    http_response_code($code);
    echo json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    reply(405, ['ok' => false, 'error' => 'Alleen POST is toegestaan.']);
}

// Alleen aanvragen vanaf de eigen beheerpagina
$host = $_SERVER['HTTP_HOST'] ?? '';
$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
if ($origin !== '' && parse_url($origin, PHP_URL_HOST) !== $host) {
    reply(403, ['ok' => false, 'error' => 'Aanvraag van een andere website geweigerd.']);
}
if (($_SERVER['HTTP_X_LR_BEHEER'] ?? '') !== '1') {
    reply(403, ['ok' => false, 'error' => 'Ontbrekende beheer-header.']);
}

$raw = file_get_contents('php://input');
if ($raw === false || strlen($raw) > 8 * 1024 * 1024) {
    reply(413, ['ok' => false, 'error' => 'Aanvraag is te groot (maximaal 8 MB).']);
}
$req = json_decode($raw, true);
if (!is_array($req) || !isset($req['data']['apps']) || !is_array($req['data']['apps'])) {
    reply(400, ['ok' => false, 'error' => 'Ongeldige gegevens: apps ontbreekt.']);
}

// apps.json controleren
$ids = [];
foreach ($req['data']['apps'] as $i => $app) {
    if (!is_array($app) || empty($app['id']) || empty($app['name'])) {
        reply(400, ['ok' => false, 'error' => 'App ' . ($i + 1) . ' mist een id of naam.']);
    }
    if (!preg_match('/^[a-z0-9-]+$/', $app['id'])) {
        reply(400, ['ok' => false, 'error' => 'Ongeldige id: ' . $app['id']]);
    }
    if (isset($ids[$app['id']])) {
        reply(400, ['ok' => false, 'error' => 'Dubbele id: ' . $app['id']]);
    }
    $ids[$app['id']] = true;
}
$json = json_encode($req['data'], JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";

// Nieuwe iconen controleren
$files = ['apps.json' => $json];
foreach (($req['files'] ?? []) as $f) {
    $path = $f['path'] ?? '';
    if (!preg_match('#^img/[a-z0-9-]+\.(webp|png|jpg)$#', $path)) {
        reply(400, ['ok' => false, 'error' => 'Ongeldig bestandspad: ' . $path]);
    }
    $bin = base64_decode($f['data'] ?? '', true);
    if ($bin === false || strlen($bin) > 2 * 1024 * 1024 || @getimagesizefromstring($bin) === false) {
        reply(400, ['ok' => false, 'error' => 'Ongeldige afbeelding: ' . $path]);
    }
    $files[$path] = $bin;
}

// 1. Direct live zetten op deze server
foreach ($files as $path => $content) {
    $target = __DIR__ . '/' . $path;
    if (!is_dir(dirname($target))) @mkdir(dirname($target), 0755, true);
    $tmp = $target . '.tmp';
    if (@file_put_contents($tmp, $content) === false || !@rename($tmp, $target)) {
        @unlink($tmp);
        reply(500, ['ok' => false, 'error' => 'Kon ' . $path . ' niet opslaan op de server. Controleer de schrijfrechten.']);
    }
}

// 2. Eén commit naar GitHub
$cfgFile = __DIR__ . '/.publish-config.php';
if (!is_file($cfgFile)) {
    reply(200, ['ok' => true, 'live' => true, 'github' => false,
        'warning' => 'Live gezet, maar niet in GitHub opgeslagen: secret PUBLISH_GITHUB_TOKEN ontbreekt. Een volgende deploy overschrijft deze wijziging.']);
}
$cfg = require $cfgFile;

function gh(string $method, string $url, array $cfg, ?array $body = null): array {
    $ch = curl_init('https://api.github.com/repos/' . $cfg['repo'] . $url);
    curl_setopt_array($ch, [
        CURLOPT_CUSTOMREQUEST => $method,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 30,
        CURLOPT_HTTPHEADER => [
            'Authorization: Bearer ' . $cfg['token'],
            'Accept: application/vnd.github+json',
            'X-GitHub-Api-Version: 2022-11-28',
            'User-Agent: lrvdlinden-beheer',
            'Content-Type: application/json',
        ],
    ]);
    if ($body !== null) curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body));
    $res = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err = curl_error($ch);
    curl_close($ch);
    $data = json_decode((string)$res, true) ?: [];
    if ($code < 200 || $code >= 300) {
        throw new RuntimeException('GitHub ' . $method . ' ' . $url . ' gaf HTTP ' . $code . ': ' . ($data['message'] ?? $err));
    }
    return $data;
}

try {
    $branch = $cfg['branch'] ?? 'main';
    $ref = gh('GET', '/git/ref/heads/' . $branch, $cfg);
    $parent = $ref['object']['sha'];
    $base = gh('GET', '/git/commits/' . $parent, $cfg);
    $tree = [];
    foreach ($files as $path => $content) {
        $blob = gh('POST', '/git/blobs', $cfg, ['content' => base64_encode($content), 'encoding' => 'base64']);
        $tree[] = ['path' => 'site/' . $path, 'mode' => '100644', 'type' => 'blob', 'sha' => $blob['sha']];
    }
    $newTree = gh('POST', '/git/trees', $cfg, ['base_tree' => $base['tree']['sha'], 'tree' => $tree]);
    if ($newTree['sha'] === $base['tree']['sha']) {
        reply(200, ['ok' => true, 'live' => true, 'github' => true, 'unchanged' => true]);
    }
    $msg = trim((string)($req['message'] ?? ''));
    $commit = gh('POST', '/git/commits', $cfg, [
        'message' => ($msg !== '' ? mb_substr($msg, 0, 200) : 'Bijgewerkt via beheerpagina'),
        'tree' => $newTree['sha'],
        'parents' => [$parent],
    ]);
    gh('PATCH', '/git/refs/heads/' . $branch, $cfg, ['sha' => $commit['sha']]);
    reply(200, ['ok' => true, 'live' => true, 'github' => true,
        'commit' => substr($commit['sha'], 0, 7),
        'actions' => 'https://github.com/' . $cfg['repo'] . '/actions']);
} catch (Throwable $e) {
    reply(200, ['ok' => true, 'live' => true, 'github' => false,
        'warning' => 'Live gezet, maar opslaan in GitHub mislukte: ' . $e->getMessage()]);
}
