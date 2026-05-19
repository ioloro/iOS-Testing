class Iostesting < Formula
  desc "iOS/macOS test runner CLI: simulators, devices, XCTest bundles"
  homepage "https://github.com/ioloro/iOS-Testing"
  license "MIT"
  head "https://github.com/ioloro/iOS-Testing.git", branch: "main"

  # version + url + sha256 get pinned when we cut a release. The template below
  # shows the shape; bump these in lockstep with package.json / SKILL.md /
  # CHANGELOG.md (scripts/check-version-drift.sh enforces this in CI).
  #
  # url "https://github.com/ioloro/iOS-Testing/archive/refs/tags/v1.2.0.tar.gz"
  # sha256 "<run `shasum -a 256` on the tarball>"
  # version "1.2.0"

  depends_on xcode: ["14.0", :build]
  depends_on macos: :ventura

  def install
    cd "cli" do
      system "swift", "build",
             "--disable-sandbox",
             "-c", "release"
      bin.install ".build/release/iostesting"
    end
  end

  test do
    assert_match "1.", shell_output("#{bin}/iostesting --version")
    assert_match "config", shell_output("#{bin}/iostesting --help")
  end
end
