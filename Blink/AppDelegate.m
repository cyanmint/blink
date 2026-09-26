////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Copyright (C) 2016-2019 Blink Mobile Shell Project
//
// This file is part of Blink.
//
// Blink is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Blink is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Blink. If not, see <http://www.gnu.org/licenses/>.
//
// In addition, Blink is also subject to certain additional terms under
// GNU GPL version 3 section 7.
//
// You should have received a copy of these additional terms immediately
// following the terms and conditions of the GNU General Public License
// which accompanied the Blink Source Code. If not, see
// <http://www.github.com/blinksh/blink>.
//
////////////////////////////////////////////////////////////////////////////////

#import "AppDelegate.h"
#import "BKiCloudSyncHandler.h"
#import <BlinkConfig/BlinkPaths.h>
#import "BLKDefaults.h"
#import <BlinkConfig/BKHosts.h>
#import <BlinkConfig/BKPubKey.h>
#import <ios_system/ios_system.h>
#import <UserNotifications/UserNotifications.h>
#include <libssh/callbacks.h>
#include "xcall.h"
#include "Blink-Swift.h"
#include <stdio.h>

extern int hermes_runtime_prepare(void);
extern int hermes_runtime_initialize(void);

static FILE *hermesRuntimeFallbackInput;
static FILE *hermesRuntimeFallbackOutput;
static FILE *hermesRuntimeFallbackError;

static FILE *HermesLinkRuntimeStream(FILE *current, FILE *standard,
                                     FILE **fallback, const char *mode) {
  if (current != NULL) return current;
  if (standard != NULL) return standard;
  if (*fallback == NULL) *fallback = fopen("/dev/null", mode);
  return *fallback;
}

static int HermesLinkInitializeCPython(void) {
  FILE *savedInput = thread_stdin;
  FILE *savedOutput = thread_stdout;
  FILE *savedError = thread_stderr;

  // CPython's iOS port resolves stdio to ios_system's TLS streams. During app
  // startup there is no command session, so temporarily provide safe streams.
  thread_stdin = HermesLinkRuntimeStream(savedInput, stdin,
                                         &hermesRuntimeFallbackInput, "r");
  thread_stdout = HermesLinkRuntimeStream(savedOutput, stdout,
                                         &hermesRuntimeFallbackOutput, "w");
  thread_stderr = HermesLinkRuntimeStream(savedError, stderr,
                                         &hermesRuntimeFallbackError, "w");

  int result = 70;
  if (thread_stdin != NULL && thread_stdout != NULL && thread_stderr != NULL) {
    result = hermes_runtime_initialize();
  } else {
    HermesLinkAppendLog("embedded CPython initialization skipped: no usable stdio streams");
  }

  thread_stdin = savedInput;
  thread_stdout = savedOutput;
  thread_stderr = savedError;
  return result;
}

#ifdef BLINK_BUILD_ENABLED
extern void build_auto_start_wg_ports(void);
extern void rebind_ports(void);
#endif


@import CloudKit;

@interface AppDelegate () <UNUserNotificationCenterDelegate>
@end

@implementation AppDelegate {
  NSTimer *_suspendTimer;
  UIBackgroundTaskIdentifier _suspendTaskId;
  BOOL _suspendedMode;
  BOOL _enforceSuspension;
}
  
void __on_pipebroken_signal(int signum){
  NSLog(@"PIPE is broken");
}

void __setupProcessEnv(void) {
  
  NSBundle *mainBundle = [NSBundle mainBundle];
  int forceOverwrite = 1;
  NSString *SSL_CERT_FILE = [mainBundle pathForResource:@"cacert" ofType:@"pem"];
  setenv("SSL_CERT_FILE", SSL_CERT_FILE.UTF8String, forceOverwrite);
  
  NSString *locales_path = [mainBundle pathForResource:@"locales" ofType:@"bundle"];
  setenv("PATH_LOCALE", locales_path.UTF8String, forceOverwrite);
  setlocale(LC_ALL, "UTF-8");
  setenv("TERM", "xterm-256color", forceOverwrite);
  setenv("LANG", "en_US.UTF-8", forceOverwrite);
  setenv("VIMRUNTIME", [[mainBundle resourcePath] stringByAppendingPathComponent:@"/vim"].UTF8String, 1);
  ssh_threads_set_callbacks(ssh_threads_get_pthread());
  ssh_init();
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  HermesLinkAppendLog("application didFinishLaunching");
  if (hermes_runtime_prepare() != 0) {
    NSLog(@"Failed to prepare Hermes CPython native modules");
  }
  
  [Migrator perform];

  [AppDelegate reloadDefaults];
  [[UIView appearance] setTintColor:[UIColor blinkTint]];
  
  signal(SIGPIPE, __on_pipebroken_signal);
 
  dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
  dispatch_async(bgQueue, ^{
    [BlinkPaths linkDocumentsIfNeeded];
    [BlinkPaths linkICloudDriveIfNeeded];
    
  });

  sideLoading = false; // Turn off extra commands from iOS system
  initializeEnvironment(); // initialize environment variables for iOS system
  NSString *commandDictionary = [[NSBundle mainBundle] pathForResource:@"blinkCommandsDictionary" ofType:@"plist"];
  NSError *commandDictionaryError = addCommandList(commandDictionary);
  if (commandDictionaryError != nil) {
    NSLog(@"Failed to register HermesLink command dictionary: %@", commandDictionaryError);
  }
  // Reassert the embedded entrypoints after ios_system's command list is built.
  // The stock a-Shell dictionary contains stale Python framework aliases; those
  // must never win over the symbols linked into HermesRuntime.framework.
  // HermesRuntime uses one process-lifetime CPython interpreter, so keep
  // ios_system from allocating multiple pythonA/pythonB framework instances.
  numPythonInterpreters = 1;
  replaceCommand(@"python", @"python_main", false);
  replaceCommand(@"python3", @"python_main", false);
  replaceCommand(@"sh", @"sh_main", false);
  replaceCommand(@"dash", @"sh_main", false);
  replaceCommand(@"hermes", @"hermes_main", false);
  dispatch_async(bgQueue, ^{
    __setupProcessEnv(); // we should call this after ios_system initializeEnvironment to override its defaults.
    [AppDelegate _loadProfileVars];
  });
  
  NSString *homePath = BlinkPaths.homePath;
  NSString *documentsPath = [homePath stringByAppendingPathComponent:@"Documents"];
  NSString *hermesHomePath = [documentsPath stringByAppendingPathComponent:@"hermes-home"];
  [[NSFileManager defaultManager] createDirectoryAtPath:documentsPath
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
  [[NSFileManager defaultManager] createDirectoryAtPath:hermesHomePath
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
  setenv("HOME", homePath.UTF8String, 1);
  setenv("SSH_HOME", homePath.UTF8String, 1);
  setenv("CURL_HOME", homePath.UTF8String, 1);
  setenv("HERMES_HOME", hermesHomePath.UTF8String, 1);
  setenv("HERMES_WEBUI_DEFAULT_WORKSPACE", documentsPath.UTF8String, 1);
  setenv("TERMINAL_CWD", documentsPath.UTF8String, 1);
  setenv("PWD", documentsPath.UTF8String, 1);

  NSString *runtimeRoot = [NSBundle mainBundle].resourcePath;
  NSString *runtimeArchive = [runtimeRoot stringByAppendingPathComponent:@"hermesrt.zip"];
  if (runtimeRoot.length > 0 &&
      [[NSFileManager defaultManager] fileExistsAtPath:runtimeArchive]) {
    setenv("HERMES_RUNTIME_ROOT", runtimeRoot.UTF8String, 1);
    if (HermesLinkInitializeCPython() != 0) {
      HermesLinkAppendLog("embedded CPython initialization failed on the main thread");
      NSLog(@"Failed to initialize embedded CPython on the main thread");
    }
  } else {
    HermesLinkAppendLog("embedded CPython initialization skipped: hermesrt.zip is missing");
  }
  
  NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
  [nc addObserver:self
         selector:@selector(_onSceneDidEnterBackground:)
             name:UISceneDidEnterBackgroundNotification object:nil];
  [nc addObserver:self
           selector:@selector(_onSceneWillEnterForeground:)
               name:UISceneWillEnterForegroundNotification object:nil];
  [nc addObserver:self
         selector:@selector(_onSceneDidActiveNotification:)
             name:UISceneDidActivateNotification object:nil];
  [nc addObserver:self
         selector: @selector(_onScreenConnect)
             name:UIScreenDidConnectNotification object:nil];
  
  [UNUserNotificationCenter currentNotificationCenter].delegate = self;
  
//  [nc addObserver:self selector:@selector(_logEvent:) name:nil object:nil];
//  [nc addObserver:self selector:@selector(_active) name:@"UIApplicationSystemNavigationActionChangedNotification" object:nil];

  [UIApplication sharedApplication].applicationSupportsShakeToEdit = NO;
  
  [_NSFileProviderManager syncWithBKHosts];
  
  [PurchasesUserModelObjc preparePurchasesUserModel];
  
#ifdef BLINK_BUILD_ENABLED
  build_auto_start_wg_ports();
#endif
  
  return YES;
}

//- (void)_active {
//  [[SmarterTermInput shared] realBecomeFirstResponder];
//}
//- (void)_logEvent:(NSNotification *)n {
//  NSLog(@"event, %@, %@", n.name, n.userInfo);
//  if ([n.name isEqualToString:@"UIApplicationSystemNavigationActionChangedNotification"]) {
//    [[SmarterTermInput shared] realBecomeFirstResponder];
//  }
//
//}

+ (void)reloadDefaults {
  [BLKDefaults loadDefaults];
  [BKPubKey loadIDS];
  [BKHosts loadHosts];
  [AppDelegate _loadProfileVars];
}

+ (void)_loadProfileVars {
  NSCharacterSet *whiteSpace = [NSCharacterSet whitespaceCharacterSet];
  NSString *profile = [NSString stringWithContentsOfFile:[BlinkPaths blinkProfileFile] encoding:NSUTF8StringEncoding error:nil];
  [profile enumerateLinesUsingBlock:^(NSString * _Nonnull line, BOOL * _Nonnull stop) {
    NSMutableArray<NSString *> *parts = [[line componentsSeparatedByString:@"="] mutableCopy];
    if (parts.count < 2) {
      return;
    }
    
    NSString *varName = [parts.firstObject stringByTrimmingCharactersInSet:whiteSpace];
    if (varName.length == 0) {
      return;
    }
    [parts removeObjectAtIndex:0];
    NSString *varValue = [[parts componentsJoinedByString:@"="] stringByTrimmingCharactersInSet:whiteSpace];
    if ([varValue hasSuffix:@"\""] || [varValue hasPrefix:@"\""]) {
      NSData *data =  [varValue dataUsingEncoding:NSUTF8StringEncoding];
      varValue = [varValue substringWithRange:NSMakeRange(1, varValue.length - 1)];
      if (data) {
        id value = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:nil];
        if ([value isKindOfClass:[NSString class]]) {
          varValue = value;
        }
      }
    }
    if (varValue.length == 0) {
      return;
    }
    BOOL forceOverwrite = 1;
    setenv(varName.UTF8String, varValue.UTF8String, forceOverwrite);
  }];
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
  [[BKiCloudSyncHandler sharedHandler]checkForReachabilityAndSync:nil];
  // TODO: pass completion handler.
}

// MARK: NSUserActivity

// Deprecated and no-ops.
// - (BOOL)application:(UIApplication *)application willContinueUserActivityWithType:(NSString *)userActivityType 
// {
//   return YES;
// }

// - (BOOL)application:(UIApplication *)application continueUserActivity:(NSUserActivity *)userActivity restorationHandler:(void (^)(NSArray * _Nullable))restorationHandler
// {
//   return YES;
// }

- (BOOL)application:(UIApplication *)application shouldAllowExtensionPointIdentifier:(NSString *)extensionPointIdentifier {
  if ([extensionPointIdentifier isEqualToString: UIApplicationKeyboardExtensionPointIdentifier]) {
    return ![BLKDefaults disableCustomKeyboards];
  }
  return YES;
}

#pragma mark - State saving and restoring

- (void)applicationProtectedDataWillBecomeUnavailable:(UIApplication *)application
{
  // If a scene is not yet in the background, then await for it to suspend
  NSArray * scenes = UIApplication.sharedApplication.connectedScenes.allObjects;
  for (UIScene *scene in scenes) {
    if (scene.activationState == UISceneActivationStateForegroundActive || scene.activationState == UISceneActivationStateForegroundInactive) {
      _enforceSuspension = true;
      return;
    }
  }

  [self _suspendApplicationOnProtectedDataWillBecomeUnavailable];
}

- (void)applicationWillTerminate:(UIApplication *)application
{
  [self _suspendApplicationOnWillTerminate];
}

- (void)_startMonitoringForSuspending
{
  if (_suspendedMode) {
    return;
  }
  
  UIApplication *application = [UIApplication sharedApplication];
  
  [self _cancelApplicationSuspendTask];
  
  _suspendTaskId = [application beginBackgroundTaskWithName:@"Suspend" expirationHandler:^{
    [self _suspendApplicationWithExpirationHandler];
  }];
  
  NSTimeInterval time = MIN(application.backgroundTimeRemaining * 0.9, 5 * 60);
  [_suspendTimer invalidate];
  _suspendTimer = [NSTimer scheduledTimerWithTimeInterval:time
                                                   target:self
                                                 selector:@selector(_suspendApplicationWithSuspendTimer)
                                                 userInfo:nil
                                                  repeats:NO];
}

- (void)_cancelApplicationSuspendTask {
  [_suspendTimer invalidate];
  if (_suspendTaskId != UIBackgroundTaskInvalid) {
    [[UIApplication sharedApplication] endBackgroundTask:_suspendTaskId];
  }
  _suspendTaskId = UIBackgroundTaskInvalid;
}

- (void)_cancelApplicationSuspend {
  [self _cancelApplicationSuspendTask];
 
  // We can't resume if we don't have access to protected data
  if (UIApplication.sharedApplication.isProtectedDataAvailable) {
    if (_suspendedMode) {
#ifdef BLINK_BUILD_ENABLED
      rebind_ports();
#endif
    }

    _suspendedMode = NO;
  }
}

// Simple wrappers to get the reason of failure from call stack
- (void)_suspendApplicationWithSuspendTimer {
  [self _suspendApplication];
}

- (void)_suspendApplicationWithExpirationHandler {
  [self _suspendApplication];
}

- (void)_suspendApplicationOnWillTerminate {
  [self _suspendApplication];
}

- (void)_suspendApplicationOnProtectedDataWillBecomeUnavailable {
  [self _suspendApplication];
}

- (void)_suspendApplication {
  [_suspendTimer invalidate];

  _enforceSuspension = false;
  
  if (_suspendedMode) {
    return;
  }
  
  [[SessionRegistry shared] suspend];
  _suspendedMode = YES;
  [self _cancelApplicationSuspendTask];
}

#pragma mark - Scenes

- (UISceneConfiguration *) application:(UIApplication *)application
configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                               options:(UISceneConnectionOptions *)options {
  // for (NSUserActivity * activity in options.userActivities) {  }
  return [UISceneConfiguration configurationWithName:@"main"
                                         sessionRole:connectingSceneSession.role];
}



- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
  [SpaceController onDidDiscardSceneSessions: sceneSessions];
}

- (void)_onSceneDidEnterBackground:(NSNotification *)notification {
  NSArray * scenes = UIApplication.sharedApplication.connectedScenes.allObjects;
  for (UIScene *scene in scenes) {
    if (scene.activationState == UISceneActivationStateForegroundActive || scene.activationState == UISceneActivationStateForegroundInactive) {
      return;
    }
  }
  if (_enforceSuspension) {
    [self _suspendApplication];
  } else {
    [self _startMonitoringForSuspending];
  }
}

- (void)_onSceneWillEnterForeground:(NSNotification *)notification {
  [self _cancelApplicationSuspend];
}

- (void)_onSceneDidActiveNotification:(NSNotification *)notification {
  [self _cancelApplicationSuspend];
}

- (void)_onScreenConnect {
  [BLKDefaults applyExternalScreenCompensation:BLKDefaults.overscanCompensation];
}

#pragma mark - UNUserNotificationCenterDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
  UNNotificationPresentationOptions opts = UNNotificationPresentationOptionSound | UNNotificationPresentationOptionList | UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionBadge;
  completionHandler(opts);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)(void))completionHandler {
  SceneDelegate *sceneDelegate = (SceneDelegate *)response.targetScene.delegate;
  
  SpaceController *ctrl = sceneDelegate.spaceController;
  
  [ctrl moveToShellWithKey:response.notification.request.content.threadIdentifier];
  
  completionHandler();
}

#pragma mark - Menu Building

- (void)buildMenuWithBuilder:(id<UIMenuBuilder>)builder {
  if (builder.system == UIMenuSystem.mainSystem) {
    [MenuController buildMenuWith:builder];
  }
}

@end
