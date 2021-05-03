@echo off
quartus_cdb marsohod2 -c marsohod2 --update_mif
quartus_asm --read_settings_files=on --write_settings_files=off marsohod2 -c marsohod2
