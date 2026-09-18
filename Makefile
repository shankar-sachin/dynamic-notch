APP      := Dynamic Notch
SCHEME   := DynamicNotch
PROJECT  := DynamicNotch.xcodeproj
CONFIG   ?= Debug
DERIVED  := build
DIST     := dist
BUNDLE   := $(DERIVED)/Build/Products/$(CONFIG)/$(APP).app
RELEASE  := $(DERIVED)/Build/Products/Release/$(APP).app
# Artifact names have no spaces: they end up in download URLs.
SLUG     := DynamicNotch
VERSION  := $(shell /usr/libexec/PlistBuddy -c "Print MARKETING_VERSION" /dev/stdin <<< "$$(plutil -convert xml1 -o - Sources/DynamicNotch/Resources/Info.plist 2>/dev/null)" 2>/dev/null || echo 1.0)

.PHONY: all project build run kill clean test install uninstall logs release dmg zip dist-clean

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

release: project ## build the optimised app
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(DERIVED) -quiet build
	@echo "▸ built $(RELEASE)"

$(DIST)/$(SLUG).app: release
	@mkdir -p $(DIST)
	@rm -rf "$(DIST)/$(APP).app"
	@cp -R "$(RELEASE)" "$(DIST)/"
	@# Ad-hoc, not the Apple Development identity: that cert is personal, and
	@# for anyone else downloading this it buys nothing — without a Developer ID
	@# and notarisation, Gatekeeper stops it either way.
	@codesign --force --sign - --timestamp=none "$(DIST)/$(APP).app"
	@codesign --verify --strict "$(DIST)/$(APP).app" && echo "▸ signed (ad-hoc)"

dmg: $(DIST)/$(SLUG).app ## build a drag-to-install .dmg for a GitHub release
	@rm -rf "$(DIST)/stage" "$(DIST)/$(SLUG)-$(VERSION).dmg"
	@mkdir -p "$(DIST)/stage"
	@cp -R "$(DIST)/$(APP).app" "$(DIST)/stage/"
	@ln -s /Applications "$(DIST)/stage/Applications"
	@cp $(DIST)/INSTALL.txt "$(DIST)/stage/" 2>/dev/null || true
	@hdiutil create -volname "$(APP)" -srcfolder "$(DIST)/stage" \
		-ov -format UDZO -quiet "$(DIST)/$(SLUG)-$(VERSION).dmg"
	@rm -rf "$(DIST)/stage"
	@echo "▸ $(DIST)/$(SLUG)-$(VERSION).dmg  ($$(du -h "$(DIST)/$(SLUG)-$(VERSION).dmg" | cut -f1))"

zip: $(DIST)/$(SLUG).app ## zip the app, preserving its signature
	@rm -f "$(DIST)/$(SLUG)-$(VERSION).zip"
	@ditto -c -k --sequesterRsrc --keepParent \
		"$(DIST)/$(APP).app" "$(DIST)/$(SLUG)-$(VERSION).zip"
	@echo "▸ $(DIST)/$(SLUG)-$(VERSION).zip  ($$(du -h "$(DIST)/$(SLUG)-$(VERSION).zip" | cut -f1))"

dist-clean:
	@rm -rf $(DIST)

logs: ## stream the app's own log messages
	@/usr/bin/log stream --info --debug --style compact --predicate 'subsystem == "com.sachi.DynamicNotch"'

clean:
	@rm -rf $(DERIVED) $(PROJECT)
