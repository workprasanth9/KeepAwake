SWIFT ?= swift

.PHONY: help build test universal menu pkg clean

help:
	@echo "Targets: build, test, universal, menu, pkg, clean"

build:
	$(SWIFT) build -c release

test:
	$(SWIFT) test

universal:
	./Scripts/build-universal.sh

menu:
	./Scripts/package-menu-app.sh

pkg:
	./Scripts/build-pkg.sh

clean:
	$(SWIFT) package clean
	rm -rf dist
