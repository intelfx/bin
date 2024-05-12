#DESTDIR ?= $(HOME)/bin/tools

CC = gcc
CXX = $(if $(filter clang,$(notdir $(CC))),clang++,g++)
RUSTC = rustc

ALLFLAGS ?= 
CFLAGS ?= -march=native -ggdb3 -O2
CXXFLAGS ?= -march=native -ggdb3 -O2
LDFLAGS ?= 
RUSTFLAGS ?= -C target-cpu=native -C opt-level=3

override CFLAGS := -Wall -Wextra -std=c11 $(ALLFLAGS) $(CFLAGS)
override CXXFLAGS := -Wall -Wextra -std=c++20 $(ALLFLAGS) $(CXXFLAGS)
override LDFLAGS := -Wl,-O1,--relax,--sort-common,--as-needed,-z,relro,-z,now,-z,pack-relative-relocs -fuse-ld=mold $(ALLFLAGS) $(LDFLAGS)
override LDLIBS := -ldl -lm -lrt -lpthread $(LDLIBS)
override RUSTFLAGS := 

install-%: %
	install -m755 $< $(DESTDIR)

%: %.asm
	nasm -f elf32 $< -o $@.o
	$(CC) -m32 $(LDFLAGS) $@.o $(LDLIBS) -o $@

%: %.rs
	$(RUSTC) $< -o $@
