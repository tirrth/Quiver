.PHONY: all build install run dmg clean xcode

APP = build/Quiver.app

all: build

# Open the project in Xcode for editing / autocomplete / SwiftUI Previews.
# (Editor only — the real signed app still comes from build.sh / `make build`.)
xcode:
	xed .

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
