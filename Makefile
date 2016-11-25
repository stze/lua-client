# This Makefile's only purpose is to simplify creating/maintaining a
# development environment. It will setup a project-private prefix(.deps/usr)
# with all dependencies required for building/testing
#
# local.mk is ignored by git and can be used for developer-specific
# customizations, which can be:
# - override default target
# - define custom targets
# - override ovariables defined here(all variables are defined with ?=)
-include local.mk

# Dependencies prefix
DEPS_DIR ?= $(shell pwd)/.deps
DEPS_PREFIX ?= $(DEPS_DIR)/usr
DEPS_BIN ?= $(DEPS_PREFIX)/bin

# Lua-related configuration
LUA_URL ?= http://www.lua.org/ftp/lua-5.1.5.tar.gz
LUAROCKS_URL ?= https://github.com/keplerproject/luarocks/archive/v2.2.0.tar.gz
LUA_TARGET ?= linux
LUA ?= $(DEPS_BIN)/lua
LUAROCKS ?= $(DEPS_BIN)/luarocks
BUSTED ?= $(DEPS_BIN)/busted
LUV ?= $(DEPS_PREFIX)/lib/luarocks/rocks/luv
MPACK ?= $(DEPS_PREFIX)/lib/luarocks/rocks/mpack
COXPCALL ?= $(DEPS_PREFIX)/lib/luarocks/rocks/coxpcall
LUATWEETNACL ?= $(DEPS_PREFIX)/lib/luarocks/rocks/luatweetnacl
STRUCT ?= $(DEPS_PREFIX)/lib/luarocks/rocks/struct
POSIX ?= $(DEPS_PREFIX)/lib/luarocks/rocks/posix
LUABITOP ?= $(DEPS_PREFIX)/lib/luarocks/rocks/luabitop
LUAGCRYPT ?= $(DEPS_PREFIX)/lib/luarocks/rocks/luagcrypt


# Compilation
CC ?= gcc
CFLAGS ?= -g -fPIC -Wall -Wextra -Werror -Wconversion -Wextra \
	-Wstrict-prototypes -pedantic
LDFLAGS ?= -shared -fPIC
DEPS_INCLUDE_FLAGS ?= -I$(DEPS_PREFIX)/include

# Misc
# Options used by the 'valgrind' target, which runs the tests under valgrind
VALGRIND_OPTS ?= --log-file=valgrind.log --leak-check=yes --track-origins=yes
# Command that will download a file and pipe it's contents to stdout
FETCH ?= curl -L -o -
# Command that will gunzip/untar a file from stdin to the current directory,
# stripping one directory component
UNTGZ ?= tar xfz - --strip-components=1


all: deps splonebox/native.so

deps: | $(MPACK) $(COXPCALL) $(BUSTED) $(LUV) $(NACL) $(STRUCT) $(POSIX) \
		$(LUABITOP) $(LUAGCRYPT)

test: all
	$(BUSTED) -v '--lpath=./splonebox/?.lua;' '--cpath=./splonebox/?.so;' -o gtest test

valgrind: all
	eval $$($(LUAROCKS) path); \
	valgrind $(VALGRIND_OPTS) $(LUA) \
		$(DEPS_PREFIX)/lib/luarocks/rocks/busted/2.0.rc11-0/bin/busted \
		'--lpath=./splonebox/?.lua;' '--cpath=./splonebox/?.so;' test
	cat valgrind.log

clean:
	rm -f splonebox/*.o splonebox/*.so

distclean: clean
	rm -rf $(DEPS_DIR)

splonebox/native.o: splonebox/native.c $(LUA) $(LIBUV)
	$(CC) $(CFLAGS) -o $@ -c $< $(DEPS_INCLUDE_FLAGS)

splonebox/native.so: splonebox/native.o
	$(CC) $(LDFLAGS) $< -o $@

$(BUSTED): | $(LUAROCKS)
	$(LUAROCKS) install busted
	$(LUAROCKS) install inspect  # helpful for debugging

$(LUV): $(LUAROCKS)
	$(LUAROCKS) install luv

$(MPACK): $(LUAROCKS)
	$(LUAROCKS) install mpack

$(LUATWEETNACL): $(LUAROCKS)
	$(LUAROCKS) install luatweetnacl

$(STRUCT): $(LUAROCKS)
	$(LUAROCKS) install struct

$(POSIX): $(LUAROCKS)
	$(LUAROCKS) install luaposix

$(LUABITOP): $(LUAROCKS)
	$(LUAROCKS) install luabitop

$(COXPCALL): $(LUAROCKS)
	$(LUAROCKS) install coxpcall

$(LUAGCRYPT): $(LUAROCKS)
	$(LUAROCKS) install luagcrypt

$(LUAROCKS): $(LUA)
	dir="$(DEPS_DIR)/src/luarocks"; \
	mkdir -p $$dir && cd $$dir && \
	$(FETCH) $(LUAROCKS_URL) | $(UNTGZ) && \
	./configure --prefix=$(DEPS_PREFIX) --force-config \
		--with-lua=$(DEPS_PREFIX) && make bootstrap

$(LUA):
	dir="$(DEPS_DIR)/src/lua"; \
	mkdir -p $$dir && cd $$dir && \
	$(FETCH) $(LUA_URL) | $(UNTGZ) && \
	sed -i -e '/^CFLAGS/s/-O2/-g/' src/Makefile && \
	make $(LUA_TARGET) install INSTALL_TOP=$(DEPS_PREFIX)

.PHONY: all deps test valgrind clean distclean
