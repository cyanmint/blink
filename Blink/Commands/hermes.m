#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdint.h>

#include "ios_error.h"

extern int hermes_runtime_main(int argc, char **argv);

static NSString * const HermesLinkDiagnosticsKey = @"HermesLinkDiagnosticsEnabled";
static NSString * const HermesRuntimeTimestampEntry = @"hermes-runtime.timestamp";

void HermesLinkAppendLog(const char *message);

static BOOL HermesReadRuntimeTimestamp(NSString *path, unsigned long long *timestamp) {
  NSData *data = [NSData dataWithContentsOfFile:path options:0 error:nil];
  const unsigned char *bytes = data.bytes;
  NSUInteger length = data.length;
  for (NSUInteger offset = 0; offset + 30 <= length; offset++) {
    if (bytes[offset] != 0x50 || bytes[offset + 1] != 0x4b ||
        bytes[offset + 2] != 0x03 || bytes[offset + 3] != 0x04) continue;
    uint16_t method = bytes[offset + 8] | ((uint16_t)bytes[offset + 9] << 8);
    uint32_t size = bytes[offset + 18] | ((uint32_t)bytes[offset + 19] << 8) |
                    ((uint32_t)bytes[offset + 20] << 16) | ((uint32_t)bytes[offset + 21] << 24);
    uint16_t nameLength = bytes[offset + 26] | ((uint16_t)bytes[offset + 27] << 8);
    uint16_t extraLength = bytes[offset + 28] | ((uint16_t)bytes[offset + 29] << 8);
    NSUInteger nameOffset = offset + 30;
    NSUInteger contentOffset = nameOffset + nameLength + extraLength;
    if (contentOffset > length || nameLength == 0 || contentOffset + size > length) continue;
    NSString *name = [[NSString alloc] initWithBytes:bytes + nameOffset
                                               length:nameLength
                                             encoding:NSUTF8StringEncoding];
    if (![name isEqualToString:HermesRuntimeTimestampEntry] || method != 0) continue;
    NSString *value = [[NSString alloc] initWithBytes:bytes + contentOffset
                                                length:size
                                              encoding:NSUTF8StringEncoding];
    if (value.length == 0) return NO;
    const char *text = value.UTF8String;
    if (text == NULL) return NO;
    char *end = NULL;
    unsigned long long parsed = strtoull(text, &end, 10);
    if (end == text || *end != '\0' || parsed == 0) return NO;
    *timestamp = parsed;
    return YES;
  }
  return NO;
}

static NSString *HermesPrepareRuntimeArchive(NSString *bundledRuntime) {
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSMutableArray<NSString *> *runtimeRoots = [NSMutableArray array];
  // A runtime explicitly copied to the shell user's ~/Documents is the
  // user-selected runtime and must win over an older cached/bundled copy.
  const char *home = getenv("HOME");
  if (home != NULL && home[0] != '\0') {
    NSString *shellHomeDocuments = [[NSString stringWithUTF8String:home] stringByAppendingPathComponent:@"Documents"];
    if (shellHomeDocuments.length > 0) [runtimeRoots addObject:shellHomeDocuments];
  }
  const char *environmentRoots[] = { getenv("HERMES_HOME"), getenv("TERMINAL_CWD"), getenv("HOME") };
  for (NSUInteger index = 0; index < sizeof(environmentRoots) / sizeof(environmentRoots[0]); index++) {
    if (environmentRoots[index] != NULL && environmentRoots[index][0] != '\0') {
      [runtimeRoots addObject:[NSString stringWithUTF8String:environmentRoots[index]]];
    }
  }
  NSString *homeDocuments = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
  if (homeDocuments.length > 0) [runtimeRoots addObject:homeDocuments];
  NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
  if (documents.length > 0) [runtimeRoots addObject:documents];
  NSString *runtimeRoot = nil;
  for (NSString *candidate in runtimeRoots) {
    if ([fileManager fileExistsAtPath:[candidate stringByAppendingPathComponent:@"hermesrt.zip"]]) {
      runtimeRoot = candidate;
      break;
    }
  }
  if (runtimeRoot.length == 0) {
    runtimeRoot = runtimeRoots.firstObject;
  }
  if (runtimeRoot.length == 0) return bundledRuntime;
  [fileManager createDirectoryAtPath:runtimeRoot withIntermediateDirectories:YES attributes:nil error:nil];
  NSString *localRuntime = [runtimeRoot stringByAppendingPathComponent:@"hermesrt.zip"];
  unsigned long long bundledTimestamp = 0;
  unsigned long long localTimestamp = 0;
  BOOL hasBundledTimestamp = HermesReadRuntimeTimestamp(bundledRuntime, &bundledTimestamp);
  BOOL hasLocalTimestamp = HermesReadRuntimeTimestamp(localRuntime, &localTimestamp);
  BOOL shouldInstall = ![fileManager fileExistsAtPath:localRuntime] ||
                       (hasBundledTimestamp && (!hasLocalTimestamp || bundledTimestamp > localTimestamp));
  if (shouldInstall) {
    NSString *temporary = [localRuntime stringByAppendingString:@".new"];
    NSError *error = nil;
    [fileManager removeItemAtPath:temporary error:nil];
    if ([fileManager copyItemAtPath:bundledRuntime toPath:temporary error:&error]) {
      [fileManager removeItemAtPath:localRuntime error:nil];
      if (![fileManager moveItemAtPath:temporary toPath:localRuntime error:&error]) {
        [fileManager removeItemAtPath:temporary error:nil];
      }
    }
    if (error != nil) {
      HermesLinkAppendLog([[NSString stringWithFormat:@"runtime archive sync failed: %@", error] UTF8String]);
    }
  }
  return [fileManager fileExistsAtPath:localRuntime] ? localRuntime : bundledRuntime;
}

BOOL HermesLinkDiagnosticsEnabled(void) {
  id value = [[NSUserDefaults standardUserDefaults] objectForKey:HermesLinkDiagnosticsKey];
  return value == nil ? NO : [value boolValue];
}

void HermesLinkSetDiagnosticsEnabled(BOOL enabled) {
  [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:HermesLinkDiagnosticsKey];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

void HermesLinkAppendLog(const char *message) {
  @autoreleasepool {
    if (!HermesLinkDiagnosticsEnabled()) {
      return;
    }
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (documents.length == 0) {
      documents = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:documents withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [documents stringByAppendingPathComponent:@"hermeslink.log"];
    NSString *timestamp = [[NSISO8601DateFormatter new] stringFromDate:[NSDate date]];
    NSString *line = [NSString stringWithFormat:@"[%@] pid=%d tid=%p %s\n", timestamp, getpid(), [NSThread currentThread], message ?: ""];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    @synchronized (path) {
      NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
      if (handle) {
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle synchronizeFile];
        [handle closeFile];
      } else {
        [data writeToFile:path options:NSDataWritingAtomic error:nil];
      }
    }
  }
}

__attribute__((visibility("default")))
int HermesLinkOutputFD(int error_stream) {
  FILE *stream = error_stream ? thread_stderr : thread_stdout;
  return stream == NULL ? -1 : fileno(stream);
}

__attribute__((visibility("default")))
int HermesLinkInputFD(void) {
  return thread_stdin == NULL ? -1 : fileno(thread_stdin);
}

__attribute__((visibility("default")))
int hermes_main(int argc, char *argv[]) {
  HermesLinkAppendLog("hermes command entered");
  // --version is a local metadata query. Do not start the embedded Python
  // interpreter for it: ios_execv can otherwise leave the terminal waiting
  // for the child runtime even though no Python work is required.
  if (argc == 2 && strcmp(argv[1], "--version") == 0) {
    fprintf(thread_stdout, "Hermes Agent v0.21.2\n");
    fflush(thread_stdout);
    return 0;
  }

  NSBundle *bundle = [NSBundle mainBundle];
  NSString *framework = [bundle.privateFrameworksPath stringByAppendingPathComponent:@"HermesRuntime.framework/HermesRuntime"];
  NSString *bundledRuntime = [bundle pathForResource:@"hermesrt" ofType:@"zip"];

  if (![[NSFileManager defaultManager] fileExistsAtPath:framework] || bundledRuntime.length == 0) {
    fprintf(thread_stderr,
            "hermes: embedded runtime is incomplete (framework=%s, hermesrt.zip=%s)\n",
            [[NSFileManager defaultManager] fileExistsAtPath:framework] ? "ok" : "missing",
            bundledRuntime.length ? "ok" : "missing");
    return 127;
  }

  NSString *runtime = HermesPrepareRuntimeArchive(bundledRuntime);
  NSString *runtimeRoot = [runtime stringByDeletingLastPathComponent];
  setenv("HERMES_RUNTIME_ROOT", runtimeRoot.UTF8String, 1);

  // The runtime is linked into HermesRuntime.framework. Calling its exported
  // entry point keeps execution in this ios_system command thread and avoids
  // ios_execv redispatching the registered "hermes" command recursively.
  HermesLinkAppendLog("starting embedded Hermes runtime framework");
  int result = hermes_runtime_main(argc, argv);
  char resultMessage[96];
  snprintf(resultMessage, sizeof(resultMessage), "embedded Hermes runtime returned %d", result);
  HermesLinkAppendLog(resultMessage);
  return result;
}

__attribute__((visibility("default")))
int python_main(int argc, char *argv[]) {
  setenv("HERMES_PYTHON_MODE", "1", 1);
  int result = hermes_runtime_main(argc, argv);
  unsetenv("HERMES_PYTHON_MODE");
  return result;
}
