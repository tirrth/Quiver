.PHONY: all build install run dmg clean

APP = build/Quiver.app

all: build

# Compile Quiver.app into ./build
build:
	./build.sh

# Build, then install to ~/Applications and launch
install:
	./install.sh

# Build and launch from ./build
run: build
	open "$(APP)"

# Build a distributable disk image
dmg: build
	./scripts/make_dmg.sh

clean:
	rm -rf build
