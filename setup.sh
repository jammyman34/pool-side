#!/bin/bash
# Pool Side — one-time project setup
set -e

echo "🏊 Setting up Pool Side..."

# Check for Homebrew
if ! command -v brew &> /dev/null; then
  echo "❌ Homebrew not found. Install from https://brew.sh then re-run."
  exit 1
fi

# Install XcodeGen if needed
if ! command -v xcodegen &> /dev/null; then
  echo "📦 Installing XcodeGen..."
  brew install xcodegen
fi

# Generate Xcode project
echo "⚙️  Generating Xcode project..."
xcodegen generate

echo ""
echo "✅ Done! Open Pool Side with:"
echo "   open PoolSide.xcodeproj"
echo ""
echo "Requirements:"
echo "  • Xcode 16+ (iOS 18.2 SDK)"
echo "  • iPhone 15 Pro or newer for on-device AI (older devices get rule-based fallback)"
