APP      := Dynamic Notch
SCHEME   := DynamicNotch
PROJECT  := DynamicNotch.xcodeproj
CONFIG   ?= Debug
DERIVED  := build
BUNDLE   := $(DERIVED)/Build/Products/$(CONFIG)/$(APP).app

.PHONY: all project build run kill clean test install uninstall logs

all: build

project: ## regenerate the Xcode project from project.yml
	@xcodegen generate --quiet

build: project ## compile the app
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) -quiet build

run: build kill ## build, then relaunch
	@open "$(BUNDLE)"
	@echo "▸ $(APP) running — look up."

kill: ## quit any running copy
	@pkill -x "$(APP)" 2>/dev/null || true
	@sleep 0.2

test: project ## run unit tests
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) -quiet test

install: build ## copy into /Applications
	@pkill -x "$(APP)" 2>/dev/null || true
	@rm -rf "/Applications/$(APP).app"
	@cp -R "$(BUNDLE)" /Applications/
	@open "/Applications/$(APP).app"
	@echo "▸ installed to /Applications/$(APP).app"

uninstall:
	@pkill -x "$(APP)" 2>/dev/null || true
	@rm -rf "/Applications/$(APP).app"

logs: ## stream the app's own log messages
	@/usr/bin/log stream --info --debug --style compact --predicate 'subsystem == "com.sachi.DynamicNotch"'

clean:
	@rm -rf $(DERIVED) $(PROJECT)
