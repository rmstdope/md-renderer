# MD Viewer

A tiny read-only Markdown viewer for macOS with Finder integration.

## Install

```sh
./build.sh --install
```

This compiles the app with `swiftc` (no Xcode project needed), copies it into
`~/Applications/MD Viewer.app`, and registers it with Finder.

## Use

- Right-click a `.md` file in Finder → **Quick Actions** (or **Services**) → **Render Markdown**
- Or right-click → **Open With** → **MD Viewer**

Every file opens in its own window. Links open in your default browser. Pinch to zoom.

If "Render Markdown" doesn't show up, enable it under
System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders, or log out and back in.

## How it works

`Sources/main.swift` is a small AppKit app. It converts Markdown to HTML with the bundled
[marked](https://github.com/markedjs/marked) (`Resources/marked.min.js`, MIT) running in JavaScriptCore,
then shows the result in a `WKWebView` with JavaScript turned off.
