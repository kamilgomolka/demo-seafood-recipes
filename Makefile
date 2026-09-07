PROJECT := DemoMealRecipes.xcodeproj
SCHEME := DemoMealRecipes
SIMULATOR ?= iPhone 17 Pro
DESTINATION := platform=iOS Simulator,name=$(SIMULATOR),OS=latest
RESULT_BUNDLE := TestResults.xcresult
SWIFT_SOURCES := DemoMealRecipes DemoMealRecipesTests DemoMealRecipesUITests

.PHONY: build test destinations format lint clean

build:
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO

test:
	rm -rf $(RESULT_BUNDLE)
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' -resultBundlePath $(RESULT_BUNDLE) \
		CODE_SIGNING_ALLOWED=NO

destinations:
	xcodebuild -showdestinations -project $(PROJECT) -scheme $(SCHEME)

format:
	xcrun swift-format format --in-place --recursive --parallel $(SWIFT_SOURCES)

lint:
	xcrun swift-format lint --strict --recursive --parallel $(SWIFT_SOURCES)

clean:
	rm -rf $(RESULT_BUNDLE)
	xcodebuild clean -project $(PROJECT) -scheme $(SCHEME)
