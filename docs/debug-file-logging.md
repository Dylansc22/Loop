# Debug File Logging

Loop uses the Scribe library (`@Loggable` macro) for structured logging via `os.Logger`. These logs appear in Console.app and via `log stream`, but can be hard to capture for fast event handlers like mouse movement.

## File-based logging for hot paths

When debugging high-frequency code (mouse events, scroll handlers, etc.), write directly to a file:

```swift
// Add to the class being debugged
private static let debugLog: FileHandle? = {
    let path = "/tmp/loop-debug.log"
    FileManager.default.createFile(atPath: path, contents: nil)
    return FileHandle(forWritingAtPath: path)
}()

private func debugPrint(_ msg: String) {
    guard let fh = Self.debugLog,
          let data = (msg + "\n").data(using: .utf8) else { return }
    fh.seekToEndOfFile()
    fh.write(data)
}
```

Then call `debugPrint("tag: \(value)")` wherever needed.

## Reading logs

```bash
# Clear before a test
: > /tmp/loop-debug.log

# Tail live
tail -f /tmp/loop-debug.log

# Search after test
grep "tag" /tmp/loop-debug.log
```

## Why not print() or os_log?

- `print()` goes to stdout which is lost when the app is launched via `open`.
- `log stream --process Loop` works for Scribe logs but misses messages in tight loops due to rate limiting.
- File logging is immediate, unbuffered, and survives any launch method.

## Build location

`xcodebuild` outputs to DerivedData, not `/tmp/loop-derived/`:

```
~/Library/Developer/Xcode/DerivedData/Loop-*/Build/Products/Debug/Loop.app
```

Launch with:

```bash
pkill -x Loop; sleep 0.5
open ~/Library/Developer/Xcode/DerivedData/Loop-*/Build/Products/Debug/Loop.app
```
