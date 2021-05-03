<?php $b=file_get_contents($argv[1]);for($i=0;$i<strlen($b);$i++)printf("%02x\n",ord($b[$i]));
