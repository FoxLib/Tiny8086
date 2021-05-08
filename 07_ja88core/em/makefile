OPTS_ALL=-O3 -fsigned-char -Wno-unused-result
OPTS_SDL=`sdl-config --cflags --libs`

all:
	${CC} machine.cc ${OPTS_SDL} ${OPTS_ALL} -o machine88
	./machine88
