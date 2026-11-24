PROJECT_NAME = oh-my-git

all: linux macos windows

linux:
	mkdir -p build/$(PROJECT_NAME)-linux
	godot --headless --export-release "Linux" "build/$(PROJECT_NAME)-linux/$(PROJECT_NAME)"
	cd build && zip -r $(PROJECT_NAME)-linux.zip $(PROJECT_NAME)-linux

macos:
	mkdir -p build/$(PROJECT_NAME)-macos
	godot --headless --export-release "macOS" "build/$(PROJECT_NAME)-macos/$(PROJECT_NAME).zip"

windows:
	mkdir -p build/$(PROJECT_NAME)-windows
	godot --headless --export-release "Windows" "build/$(PROJECT_NAME)-windows/$(PROJECT_NAME).exe"
	cd build && zip -r $(PROJECT_NAME)-windows.zip $(PROJECT_NAME)-windows

clean-unzipped:
	rm -rf build/$(PROJECT_NAME)-linux
	rm -rf build/$(PROJECT_NAME)-macos
	rm -rf build/$(PROJECT_NAME)-windows

