.PHONY: build test test-integration app app-dev run run-live capture sandbox-up sandbox-down sandbox-status canary icon install clean

APP := build/Reclaim.app

build:
	swift build

# Unit tests: built outside the sandbox, executed inside it.
test:
	Scripts/test.sh

# Integration tests against the throwaway RTEST-* disks (fresh fixtures every run).
test-integration:
	Scripts/sandbox.sh reset
	Scripts/test.sh --integration

app:
	Scripts/build-app.sh

app-dev:
	Scripts/build-app.sh --arch arm64 --debug

# Sandboxed: only RTEST-* volumes are visible and the kernel blocks writes elsewhere.
run: app-dev
	Scripts/run-sandboxed.sh $(APP)/Contents/MacOS/Reclaim --sandbox

# Real mode, real drives. For humans only.
run-live: app
	open $(APP)

# The running app renders its own windows to PNG (no Screen Recording permission needed).
capture: app-dev
	Scripts/run-sandboxed.sh $(APP)/Contents/MacOS/Reclaim --sandbox --capture "$${RECLAIM_SANDBOX_DIR:-$${TMPDIR}reclaim-sandbox}/captures"

sandbox-up:
	Scripts/sandbox.sh up
	Scripts/sandbox.sh seed

sandbox-down:
	Scripts/sandbox.sh down

sandbox-status:
	Scripts/sandbox.sh status

canary:
	Scripts/run-sandboxed.sh --canary-only

# The icon shares the mark's geometry with the app, so the script is compiled together with it.
icon:
	mkdir -p build
	xcrun swiftc -parse-as-library -O -o build/make-icon Scripts/make-icon.swift Sources/ReclaimUI/Brand/BrandGeometry.swift
	build/make-icon Resources/AppIcon.icns

install: app
	rm -rf /Applications/Reclaim.app
	cp -R $(APP) /Applications/Reclaim.app

clean:
	rm -rf .build build
