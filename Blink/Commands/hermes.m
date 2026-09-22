#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "ios_error.h"

extern int hermes_runtime_main(int argc, char **argv);

static NSString * const HermesLinkDiagnosticsKey = @"HermesLinkDiagnosticsEnabled";

BOOL HermesLinkDiagnosticsEnabled(void) {
  id value = [[NSUserDefaults standardUserDefaults] objectForKey:HermesLinkDiagnosticsKey];
  return value == nil ? YES : [value boolValue];
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
  NSString *runtime = [bundle pathForResource:@"hermesrt" ofType:@"zip"];

  if (![[NSFileManager defaultManager] fileExistsAtPath:framework] || runtime.length == 0) {
    fprintf(thread_stderr,
            "hermes: embedded runtime is incomplete (framework=%s, hermesrt.zip=%s)\n",
            [[NSFileManager defaultManager] fileExistsAtPath:framework] ? "ok" : "missing",
            runtime.length ? "ok" : "missing");
    return 127;
  }

  NSString *runtimeRoot = bundle.resourcePath;
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
