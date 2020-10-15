<?php
$a=file_get_contents($argv[1]);
for($i=0;$i<strlen($a);$i++) echo sprintf("%02x\n",ord($a[$i]));
