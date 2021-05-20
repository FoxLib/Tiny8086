<?php

$data = file_get_contents($argv[1]);
$size = (int) @ $argv[2];
$len  = strlen($data);

if (empty($size)) { echo "size required\n"; exit(1); }

?>
WIDTH=8;
DEPTH=<?=$size;?>;
ADDRESS_RADIX=HEX;
DATA_RADIX=HEX;
CONTENT BEGIN
<?php

for ($n = 0; $n < $len; $n++) {
    echo sprintf("  %x: %02x;\n", $n, ord($data[$n]));
}

echo "  [".sprintf("%x..%x]: 00;\n", $len, $size-1);
?>
END;

