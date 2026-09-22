<?php
// Inject scalar parameters into Mautic's local.php.
//
// Usage: php set-local-params.php <local.php> KEY=value [KEY=value ...]
//
// Used by the one-shot init service so admin credentials can be supplied to
// `mautic:install` without passing them on the command line. The local.php
// array terminator is the final "\n);"; assignments are appended AFTER it
// (appending before it would nest statements inside the array literal) and
// values are escaped for a single-quoted PHP literal.

$path = $argv[1] ?? '';
$pairs = array_slice($argv, 2);

if ($path === '' || !is_file($path)) {
    fwrite(STDERR, "set-local-params: no such file: {$path}\n");
    exit(1);
}

$text = file_get_contents($path);
if ($text === false) {
    fwrite(STDERR, "set-local-params: cannot read {$path}\n");
    exit(1);
}

$needle = "\n);";
$pos = strrpos($text, $needle);
if ($pos === false) {
    fwrite(STDERR, "set-local-params: array terminator not found in {$path}\n");
    exit(1);
}
$insert_at = $pos + strlen($needle);

$lines = '';
foreach ($pairs as $pair) {
    $key = '';
    $value = '';
    if (strpos($pair, '=') !== false) {
        [$key, $value] = explode('=', $pair, 2);
    } else {
        $key = $pair;
    }
    if (!preg_match('/^[a-z_][a-z0-9_]*$/', $key)) {
        fwrite(STDERR, "set-local-params: refusing unsafe key: {$key}\n");
        exit(1);
    }
    $escaped = str_replace(['\\', "'"], ['\\\\', "\\'"], $value);
    $lines .= "\n\$parameters['{$key}'] = '{$escaped}';";
}

$text = substr($text, 0, $insert_at) . $lines . substr($text, $insert_at);
if ($text === '' || substr($text, -1) !== "\n") {
    $text .= "\n";
}
file_put_contents($path, $text);

$names = array_map(
    fn($p) => strpos($p, '=') !== false ? explode('=', $p, 2)[0] : $p,
    $pairs
);
echo "set-local-params: updated {$path}: " . implode(', ', $names) . "\n";
