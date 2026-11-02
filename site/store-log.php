<?php
/**
 * Logboek in beheer.html: uitkomst van "Apps bijwerken", "Nieuwe apps ophalen" en de dagelijkse check.
 * GET  →  {"ok":true,"runs":[...],"active":[...]}
 *   runs:   logs/store-check.json uit de repo (elke run met wijzigingen en gecontroleerde versies)
 *   active: runs op GitHub die nog bezig zijn of mislukten (die staan nog niet in het logboek)
 *
 * Beveiligd met dezelfde login als beheer.html (zie .htaccess).
 */

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function reply(int $code, array $body): void {
    http_response_code($code);
    echo json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

if (($_SERVER['HTTP_X_LR_BEHEER'] ?? '') !== '1') reply(403, ['ok' => false, 'error' => 'Ontbrekende beheer-header.']);
$cfgFile = __DIR__ . '/.publish-config.php';
if (!is_file($cfgFile)) reply(200, ['ok' => false, 'error' => 'De GitHub-token ontbreekt op de server (secret PUBLISH_GITHUB_TOKEN).']);
$cfg = require $cfgFile;

function gh(string $url, array $cfg, bool $raw = false) {
    $ch = curl_init('https://api.github.com/repos/' . $cfg['repo'] . $url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 20,
        CURLOPT_HTTPHEADER => [
            'Authorization: Bearer ' . $cfg['token'],
            'Accept: ' . ($raw ? 'application/vnd.github.raw+json' : 'application/vnd.github+json'),
            'X-GitHub-Api-Version: 2022-11-28',
            'User-Agent: lrvdlinden-beheer',
        ],
    ]);
    $res = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    return [$code, $raw ? (string)$res : (json_decode((string)$res, true) ?: [])];
}

$branch = rawurlencode($cfg['branch'] ?? 'main');
[$code, $raw] = gh('/contents/logs/store-check.json?ref=' . $branch, $cfg, true);
$runs = [];
if ($code === 200) {
    $book = json_decode($raw, true);
    $runs = is_array($book['runs'] ?? null) ? $book['runs'] : [];
} elseif ($code !== 404) {
    reply(200, ['ok' => false, 'error' => 'GitHub gaf HTTP ' . $code . ' bij het ophalen van het logboek.']);
}

// Lopende en mislukte runs (die schrijven (nog) niets in het logboek)
$known = array_flip(array_map(fn($r) => (string)($r['id'] ?? ''), $runs));
$active = [];
[$c2, $list] = gh('/actions/workflows/store-check.yml/runs?per_page=20', $cfg);
if ($c2 === 200) {
    foreach ($list['workflow_runs'] ?? [] as $r) {
        $id = (string)$r['id'];
        if (isset($known[$id])) continue;
        $status = $r['status'] ?? '';
        $concl = $r['conclusion'] ?? '';
        if ($status === 'completed' && $concl === 'success') continue; // overgeslagen geplande run (niet 08:00)
        if ($status === 'completed' && $concl === 'cancelled') continue;
        $active[] = [
            'id' => $id,
            'time' => $r['run_started_at'] ?? $r['created_at'] ?? '',
            'trigger' => ($r['event'] ?? '') === 'schedule' ? 'schedule' : 'manual',
            'state' => $status === 'completed' ? 'failed' : 'running',
            'url' => $r['html_url'] ?? '',
        ];
    }
}
reply(200, ['ok' => true, 'runs' => $runs, 'active' => $active]);
