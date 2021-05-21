<?php

// php v320test.php && php bin2mif.php v320.bin 262144 > ../de0/memory.mif

$data = '';
for ($i = 0; $i < 256*1024; $i++) {

    $a0 = (256-64)*1024;
    if ($i < $a0) $b = 0;
    else {
        $x = ($i - $a0) % 320;
        $y = (int)(($i - $a0) / 320);
        $b = $x*$y;
    }

    $data .= chr($b & 255);
}

file_put_contents("v320.bin", $data);
