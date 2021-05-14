OPTS_ALL=-O3 -fsigned-char -Wno-unused-result
OPTS_SDL=`sdl-config --cflags --libs`

all:
	make build
build:
	${CC} machine.cc ${OPTS_SDL} ${OPTS_ALL} -o machine88
run:
	make bios
	./machine88
bios:
	cd ../bios && make
