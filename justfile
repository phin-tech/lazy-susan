set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

# Regenerate LazySusan.xcodeproj from project.yml
gen:
    xcodegen generate --use-cache

# Build the app (Debug)
build: gen
    xcodebuild -project LazySusan.xcodeproj -scheme LazySusan -allowProvisioningUpdates -quiet build

# Run the tests
test: gen
    xcodebuild -project LazySusan.xcodeproj -scheme LazySusan -allowProvisioningUpdates -quiet test

# Build and launch the app
run: build
    -osascript -e 'quit app id "tech.phin.LazySusan"' 2>/dev/null
    open "$(xcodebuild -project LazySusan.xcodeproj -scheme LazySusan -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{print $3}')/Lazy Susan.app"

import 'release.just'
