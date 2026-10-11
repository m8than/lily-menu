PREFIX ?= $(HOME)/Applications
APP := $(PREFIX)/LilyMenu.app

.PHONY: build test app zip install uninstall icon clean

build:
	swift build

test:
	swift test

app:
	scripts/bundle.sh

zip:
	scripts/bundle.sh --zip

install: app
	pkill -x LilyMenu || true
	rm -rf "$(APP)"
	mkdir -p "$(PREFIX)"
	ditto dist/LilyMenu.app "$(APP)"
	open "$(APP)"

uninstall:
	pkill -x LilyMenu || true
	rm -rf "$(APP)"
	defaults delete com.lily.menu 2>/dev/null || true

icon:
	swift scripts/make-icon.swift Resources/AppIcon.icns

clean:
	rm -rf .build dist
