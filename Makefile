SWIFT ?= swift

.PHONY: help build test universal menu pkg release clean

help:
	@echo "Targets: build, test, universal, menu, pkg, release, clean"

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

release:
	./Scripts/build-release.sh

clean:
	$(SWIFT) package clean
	rm -rf dist
