#import <Foundation/Foundation.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "ios_system/ios_system.h"
#include "ios_error.h"

__attribute__((visibility("default")))
int hermes_main(int argc, char *argv[]) {
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
