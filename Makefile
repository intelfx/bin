DESTDIR ?= $(HOME)/bin

CC = clang
CXX = clang++
RUSTC = rustc

CFLAGS += -g -O3 -Wall -Wextra -std=c99 -DLOCAL
CXXFLAGS += -g -O3 -Wall -Wextra -std=c++14
LDFLAGS += -rdynamic -Wl,-O1,--relax,-z,relro,--sort-common
LDLIBS += -ldl -lm -lrt -lpthread

install-%: %
	install -m755 $< $(DESTDIR)

%: %.asm
	nasm -f elf32 $< -o $@.o
	$(CC) -m32 $(LDFLAGS) $@.o $(LDLIBS) -o $@

%: %.rs
	$(RUSTC) $< -o $@
