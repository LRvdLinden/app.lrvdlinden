<?php
/**
 * Knop "Vertaal NL → EN" in beheer.html.
 * POST {"items":[{"text":"...","to":"en"|"nl"}]}  →  {"ok":true,"texts":["...", ...]}
 *
 * Beveiligd met dezelfde login als beheer.html (zie .htaccess).
 * De API-sleutel staat in .translate-config.php, die de deploy aanmaakt uit secret ANTHROPIC_API_KEY.
 */

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function reply(int $code, array $body): void {
    http_response_code($code);
    echo json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') reply(405, ['ok' => false, 'error' => 'Alleen POST is toegestaan.']);
if (($_SERVER['HTTP_X_LR_BEHEER'] ?? '') !== '1') reply(403, ['ok' => false, 'error' => 'Ontbrekende beheer-header.']);

$cfgFile = __DIR__ . '/.translate-config.php';
if (!is_file($cfgFile)) {
    reply(200, ['ok' => false, 'error' => 'Vertalen is niet ingesteld op de server: secret ANTHROPIC_API_KEY ontbreekt. Voeg die toe en draai Release site opnieuw.']);
}
$cfg = require $cfgFile;

$req = json_decode(file_get_contents('php://input') ?: '', true);
$items = $req['items'] ?? null;
if (!is_array($items) || !$items || count($items) > 60) {
    reply(400, ['ok' => false, 'error' => 'Geef 1 tot 60 teksten om te vertalen.']);
}
$payload = [];
foreach ($items as $i => $it) {
    $text = trim((string)($it['text'] ?? ''));
    $to = ($it['to'] ?? '') === 'nl' ? 'Dutch' : 'English';
    if ($text === '' || mb_strlen($text) > 6000) reply(400, ['ok' => false, 'error' => 'Tekst ' . ($i + 1) . ' is leeg of te lang.']);
    $payload[] = ['i' => $i, 'target' => $to, 'text' => $text];
}

$prompt = "Translate each text below for an app portfolio website (app subtitles, descriptions, banner texts and release notes) "
    . "into the target language. Keep the meaning, tone, line breaks, bullet characters, version numbers and product names exactly. "
    . "Use natural, informal app-store wording (Dutch: use 'je'). "
    . "Reply with only a JSON array of objects {\"i\": number, \"text\": string}, nothing else.\n\n"
    . json_encode($payload, JSON_UNESCAPED_UNICODE);

$headers = [
    'x-api-key: ' . $cfg['key'],
    'anthropic-version: 2023-06-01',
    'content-type: application/json',
];
if (!empty($cfg['workspace'])) $headers[] = 'anthropic-workspace-id: ' . $cfg['workspace'];

$ch = curl_init('https://api.anthropic.com/v1/messages');
curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT => 90,
    CURLOPT_HTTPHEADER => $headers,
    CURLOPT_POSTFIELDS => json_encode([
        'model' => $cfg['model'] ?? 'claude-haiku-5-5',
        'max_tokens' => 8000,
        'messages' => [['role' => 'user', 'content' => $prompt]],
    ]),
]);
$res = curl_exec($ch);
$code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$err = curl_error($ch);
curl_close($ch);

$data = json_decode((string)$res, true) ?: [];
if ($code < 200 || $code >= 300) {
    reply(200, ['ok' => false, 'error' => 'Vertaaldienst gaf HTTP ' . $code . ': ' . ($data['error']['message'] ?? $err ?: 'onbekende fout')]);
}
$text = '';
foreach ($data['content'] ?? [] as $c) if (($c['type'] ?? '') === 'text') $text .= $c['text'];
$start = strpos($text, '['); $end = strrpos($text, ']');
$arr = ($start !== false && $end !== false) ? json_decode(substr($text, $start, $end - $start + 1), true) : null;
if (!is_array($arr)) reply(200, ['ok' => false, 'error' => 'Het antwoord van de vertaaldienst was onleesbaar. Probeer het opnieuw.']);

$out = array_fill(0, count($items), null);
foreach ($arr as $o) {
    if (isset($o['i'], $o['text']) && is_int($o['i']) && $o['i'] >= 0 && $o['i'] < count($items)) {
        $out[$o['i']] = trim((string)$o['text']);
    }
}
reply(200, ['ok' => true, 'texts' => $out]);
