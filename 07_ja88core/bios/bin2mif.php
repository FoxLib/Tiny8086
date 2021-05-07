<?php // Создание bios.mif
$m = file_get_contents($argv[1]);

?>
WIDTH=8;
DEPTH=8192;

ADDRESS_RADIX=HEX;
DATA_RADIX=HEX;

CONTENT BEGIN
<? for ($n = 0; $n < strlen($m); $n++)
    echo sprintf("  %04x: %02x;\n", $n, ord($m[$n]));

echo "  [".sprintf("%04x", strlen($m))."..1FFF]: 00;\n";
?>
END;

