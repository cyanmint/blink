#import <Foundation/Foundation.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "ios_system/ios_system.h"
#include "ios_error.h"

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
  NSString *executable = [bundle pathForResource:@"hermes" ofType:nil];
  NSString *runtime = [bundle pathForResource:@"hermesrt" ofType:@"zip"];

  if (executable.length == 0 || runtime.length == 0) {
    fprintf(thread_stderr,
            "hermes: bundled runtime is incomplete (hermes=%s, hermesrt.zip=%s)\n",
            executable.length ? "ok" : "missing",
            runtime.length ? "ok" : "missing");
    return 127;
  }

  NSString *runtimeRoot = [runtime stringByDeletingLastPathComponent];
  setenv("HERMES_RUNTIME_ROOT", runtimeRoot.UTF8String, 1);

  char **childArgv = calloc((size_t)argc + 1, sizeof(*childArgv));
  if (childArgv == NULL) {
    fputs("hermes: unable to allocate argument vector\n", thread_stderr);
    return 70;
  }
  childArgv[0] = (char *)executable.UTF8String;
  for (int i = 1; i < argc; ++i) {
    childArgv[i] = argv[i];
  }

  int result = ios_execv(executable.fileSystemRepresentation, childArgv);
  int savedErrno = errno;
  free(childArgv);
  if (result != 0) {
    fprintf(thread_stderr, "hermes: unable to start bundled runtime: %s\n",
            strerror(savedErrno));
  }
  return result == 0 ? 0 : 126;
}
