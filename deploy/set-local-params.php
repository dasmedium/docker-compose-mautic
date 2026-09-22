<?php
// Inject scalar parameters into Mautic's local.php.
//
// Usage: php set-local-params.php <local.php> KEY=value [KEY_FILE=path ...]
//
// Two input forms are accepted, so a secret never has to appear in argv:
//
//   KEY=value           literal value (fine for non-secret values)
//   KEY_FILE=path       read the value from a file (for secret values)
//
// The local.php array terminator is the final "\n);"; assignments are appended
// AFTER it (appending before it would nest statements inside the array literal)
// and values are escaped for a single-quoted PHP literal.

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
$names = [];
foreach ($pairs as $pair) {
    if (strpos($pair, '=') === false) {
        fwrite(STDERR, "set-local-params: expected KEY=value or KEY_FILE=path: {$pair}\n");
        exit(1);
    }
    [$raw_key, $operand] = explode('=', $pair, 2);

    $from_file = false;
    if (substr($raw_key, -5) === '_FILE') {
        $from_file = true;
        $key = substr($raw_key, 0, -5);
    } else {
        $key = $raw_key;
    }

    if (!preg_match('/^[a-z_][a-z0-9_]*$/', $key)) {
        fwrite(STDERR, "set-local-params: refusing unsafe key: {$key}\n");
        exit(1);
    }

    if ($from_file) {
        if (!is_file($operand)) {
            fwrite(STDERR, "set-local-params: no such file for {$key}: {$operand}\n");
            exit(1);
        }
        $value = file_get_contents($operand);
        if ($value === false) {
            fwrite(STDERR, "set-local-params: cannot read {$operand}\n");
            exit(1);
        }
        $value = trim($value, "\r\n");
    } else {
        $value = $operand;
    }

    $escaped = str_replace(['\\', "'"], ['\\\\', "\\'"], $value);
    $lines .= "\n\$parameters['{$key}'] = '{$escaped}';";
    $names[] = $key;
}

$text = substr($text, 0, $insert_at) . $lines . substr($text, $insert_at);
if ($text === '' || substr($text, -1) !== "\n") {
    $text .= "\n";
}
file_put_contents($path, $text);

// The file now holds credentials; restrict it to the owner.
@chmod($path, 0600);

echo "set-local-params: updated {$path}: " . implode(', ', $names) . "\n";
