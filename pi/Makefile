# Compila no Raspberry Pi (ou em qualquer Linux) com:
#   sudo apt install build-essential libfftw3-dev libasound2-dev
#   make
CC      ?= gcc
CFLAGS  ?= -O3 -march=native -Wall -Wextra -std=gnu11
LDLIBS   = -lfftw3f -lm

all: pv_offline pv_alsa

pv_offline: src/pv_offline.c src/pv.c src/wav.c src/pv.h src/wav.h
	$(CC) $(CFLAGS) -o $@ src/pv_offline.c src/pv.c src/wav.c $(LDLIBS)

pv_alsa: src/pv_alsa.c src/pv.c src/pv.h
	$(CC) $(CFLAGS) -o $@ src/pv_alsa.c src/pv.c $(LDLIBS) -lasound -lpthread

clean:
	rm -f pv_offline pv_alsa

.PHONY: all clean
