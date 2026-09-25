/* HermesLink AI-generated glue code; created by cyanmint's coding agent.
 * AI-generated content has no copyright holder and is not subject to copyright. */
#import <Foundation/Foundation.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

#include "ios_error.h"

extern int hermes_runtime_main(int argc, char **argv);
extern int hermes_python_main(int argc, char **argv);
extern int ios_system(const char *inputCmd);

typedef enum {
  SHELL_CHAIN_NONE,
  SHELL_CHAIN_AND,
  SHELL_CHAIN_OR,
} HermesShellChainOperator;

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
int HermesLinkOutputFD(int error_stream) {
  FILE *stream = error_stream ? thread_stderr : thread_stdout;
  return stream == NULL ? -1 : fileno(stream);
}

__attribute__((visibility("default")))
int HermesLinkInputFD(void) {
  return thread_stdin == NULL ? -1 : fileno(thread_stdin);
}

static BOOL HermesLinkPrepareEmbeddedRuntime(void) {
  NSBundle *bundle = [NSBundle mainBundle];
  NSString *framework = [bundle.privateFrameworksPath stringByAppendingPathComponent:@"HermesRuntime.framework/HermesRuntime"];
  NSString *runtime = [bundle pathForResource:@"hermesrt" ofType:@"zip"];
  if (![[NSFileManager defaultManager] fileExistsAtPath:framework] || runtime.length == 0) {
    fprintf(thread_stderr,
            "hermes: embedded runtime is incomplete (framework=%s, hermesrt.zip=%s)\n",
            [[NSFileManager defaultManager] fileExistsAtPath:framework] ? "ok" : "missing",
            runtime.length ? "ok" : "missing");
    return NO;
  }
  setenv("HERMES_RUNTIME_ROOT", bundle.resourcePath.UTF8String, 1);
  return YES;
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

  if (!HermesLinkPrepareEmbeddedRuntime()) return 127;

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
  if (!HermesLinkPrepareEmbeddedRuntime()) return 127;
  return hermes_python_main(argc, argv);
}

static char *trim_shell_command(char *command) {
  while (isspace((unsigned char)*command)) ++command;
  char *end = command + strlen(command);
  while (end > command && isspace((unsigned char)end[-1])) --end;
  *end = '\0';
  return command;
}

static int run_shell_command(const char *input) {
  char *command = strdup(input);
  if (command == NULL) return 70;

  int result = 0;
  HermesShellChainOperator previous = SHELL_CHAIN_NONE;
  char quote = '\0';
  BOOL escaped = NO;
  char *segment = command;
  for (char *cursor = command;; ++cursor) {
    char current = *cursor;
    if (quote != '\0') {
      if (escaped) {
        escaped = NO;
      } else if (quote != '\'' && current == '\\') {
        escaped = YES;
      } else if (current == quote) {
        quote = '\0';
      }
      if (current == '\0') break;
      continue;
    }
    if (escaped) {
      escaped = NO;
      continue;
    }
    if (current == '\\') {
      escaped = YES;
      continue;
    }
    if (current == '\'' || current == '"') {
      quote = current;
      continue;
    }

    HermesShellChainOperator next = SHELL_CHAIN_NONE;
    if (current == '&' && cursor[1] == '&') next = SHELL_CHAIN_AND;
    if (current == '|' && cursor[1] == '|') next = SHELL_CHAIN_OR;
    BOOL at_end = current == '\0';
    if (next == SHELL_CHAIN_NONE && !at_end) continue;

    if (!at_end) *cursor = '\0';
    char *trimmed = trim_shell_command(segment);
    BOOL should_run = previous == SHELL_CHAIN_NONE ||
        (previous == SHELL_CHAIN_AND && result == 0) ||
        (previous == SHELL_CHAIN_OR && result != 0);
    if (*trimmed != '\0' && should_run) result = ios_system(trimmed);
    if (at_end) break;

    previous = next;
    ++cursor;
    segment = cursor + 1;
  }
  free(command);
  return result;
}

static int run_shell_stream(FILE *input, const char *name, BOOL interactive,
                            BOOL exit_on_error) {
  char *line = NULL;
  size_t capacity = 0;
  int result = 0;
  ssize_t length;
  while (1) {
    if (interactive) {
      fputs("sh$ ", thread_stdout);
      fflush(thread_stdout);
    }
    length = getline(&line, &capacity, input);
    if (length < 0) break;
    while (length > 0 && (line[length - 1] == '\n' || line[length - 1] == '\r')) {
      line[--length] = '\0';
    }
    char *command = line;
    while (*command == ' ' || *command == '\t') ++command;
    if (*command == '\0' || *command == '#') continue;
    if (strncmp(command, "exit", 4) == 0 &&
        (command[4] == '\0' || command[4] == ' ' || command[4] == '\t')) {
      char *status = command + 4;
      while (*status == ' ' || *status == '\t') ++status;
      result = *status == '\0' ? result : (int)strtol(status, NULL, 10);
      break;
    }
    result = run_shell_command(command);
    if (exit_on_error && result != 0) break;
  }
  if (ferror(input)) {
    fprintf(thread_stderr, "sh: error reading %s\n", name);
    result = 1;
  }
  free(line);
  return result;
}

static int run_shell_script(const char *path, BOOL interactive,
                            BOOL exit_on_error) {
  FILE *script = fopen(path, "r");
  if (script == NULL) {
    fprintf(thread_stderr, "sh: %s: %s\n", path, strerror(errno));
    return errno == ENOENT ? 127 : 126;
  }
  fprintf(thread_stderr,
          "sh: using line-based ios_system compatibility mode; POSIX shell syntax is unsupported in script files\n");
  int result = run_shell_stream(script, path, interactive, exit_on_error);
  fclose(script);
  return result;
}

static int run_shell_interactive(BOOL interactive, BOOL exit_on_error) {
  return run_shell_stream(thread_stdin, "stdin", interactive, exit_on_error);
}

__attribute__((visibility("default")))
int sh_main(int argc, char *argv[]) {
  BOOL read_stdin = NO;
  BOOL interactive = argc == 1 && isatty(fileno(thread_stdin));
  BOOL exit_on_error = NO;
  int argument = 1;

  while (argument < argc && argv[argument][0] == '-' &&
         strcmp(argv[argument], "-") != 0) {
    const char *option = argv[argument++];
    if (strcmp(option, "--") == 0) break;
    if (strcmp(option, "--help") == 0 || strcmp(option, "-h") == 0) {
      fprintf(thread_stdout, "usage: sh [-eis] [-c command] [file [args ...]]\n");
      return 0;
    }
    for (size_t index = 1; option[index] != '\0'; ++index) {
      switch (option[index]) {
        case 'c': {
          const char *command = option[index + 1] != '\0'
              ? &option[index + 1]
              : (argument < argc ? argv[argument++] : NULL);
          if (command == NULL) {
            fprintf(thread_stderr, "sh: -c requires a command\n");
            return 2;
          }
          return run_shell_command(command);
        }
        case 's':
          read_stdin = YES;
          break;
        case 'i':
          interactive = YES;
          break;
        case 'e':
          exit_on_error = YES;
          break;
        default:
          fprintf(thread_stderr, "sh: unsupported option: -%c\n", option[index]);
          return 2;
      }
    }
  }

  if (read_stdin || argument >= argc) {
    return run_shell_interactive(interactive, exit_on_error);
  }
  return run_shell_script(argv[argument], interactive, exit_on_error);
}
