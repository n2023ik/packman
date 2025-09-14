#!/bin/bash

# Exit on any error
set -e

# 1. Clone the Flutter SDK
git clone https://github.com/flutter/flutter.git --depth 1 --branch stable ./flutter-sdk
export PATH="$PATH:`pwd`/flutter-sdk/bin"

# 2. Get your project's dependencies
flutter pub get

# 3. Build the Flutter web app
flutter build web --release
