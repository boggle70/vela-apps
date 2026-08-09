# SPDX-License-Identifier: Apache-2.0
#
# Build in the guest - it is one file with no dependencies:
#     make
#
# Or cross-compile on the host:
#     make CC=riscv64-linux-gnu-gcc

CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra
DESTDIR ?=
PREFIX  ?= /usr/local

all: reri-inject

reri-inject: reri-inject.c
	$(CC) $(CFLAGS) -o $@ $<

install: reri-inject
	install -D -m 0755 reri-inject $(DESTDIR)$(PREFIX)/sbin/reri-inject

clean:
	rm -f reri-inject

.PHONY: all install clean
