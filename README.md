# cordova-plugin-secure-logger

Cordova plugin to capture both webview and native log events and store them securely on disk.

Pairs well with [@obsidize/rx-console](https://www.npmjs.com/package/@obsidize/rx-console)
for capturing and forwarding webview events.

## Features / Goals

- Ability to capture logs both from the webview and native side into a common **local** recording outlet
- Encrypt data before it hits the disk to protect sensitive user data
- Automatically prune oldest logs to prevent infinitely expanding log data storage

## Why make this plugin?

The most secure solution when dealing with sensitive user data is to not log anything at all.

However, when it comes to tracking down nefarious bugs that only happen in the field, the next
best thing is to capture logs in a secure sandbox - which is the aim of this plugin.

## Installation

NPM:

```bash
npm i -P -E git+https://github.com/healthrecoverysolutions/cordova-plugin-secure-logger.git#1.0.0
```

Cordova:

```bash
cordova plugin add git+https://github.com/healthrecoverysolutions/cordova-plugin-secure-logger.git#1.0.0
```

## Usage

### Logging Events

You can produce logs for this plugin on both the webview and native side like so

- TypeScript / JavaScript:

```typescript
import { SecureLogger, SecureLogLevel } from 'cordova-plugin-secure-logger';

function log(tag: string, message: string): Promise<void> {
    return SecureLogger.capture([
        {
            timestamp: Date.now(),
            level: SecureLogLevel.DEBUG,
            tag,
            message
        }
    ]);
}

log(`This will be stored in an encrypted log file`);
log(`Something interesting happened! -> ${JSON.stringify({error: `transfunctioner stopped combobulating`})}`)
```

- Android:

```kotlin
import timber.log.Timber

...

Timber.d("Logging stuff on native android for the secure logger plugin! Yay native logs!")
```

- iOS:

```swift
import CocoaLumberjack

...

DDLogDebug("Logging stuff on native ios for the secure logger plugin! Yay native logs!")
```

### Gathering Logs to Report

To grab a snapshot of the current log cache:

```typescript
import { SecureLogger } from 'cordova-plugin-secure-logger';

async function uploadLogs(): Promise<void> {
    const logCacheData = await SecureLogger.getCacheBlob();
    const bodyBlob = new Blob([logCacheData]);
    // upload / share it somewhere
    http.post('/log-capture', bodyBlob).then(...)
}
```
