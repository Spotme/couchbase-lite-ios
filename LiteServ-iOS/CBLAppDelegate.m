//
//  CBLAppDelegate.m
//  LiteServ-iOS
//
//  Created by Igor Evsukov on 12/26/13.
//
//

#import "CBLAppDelegate.h"
#import "CouchbaseLite.h"
#import "CBLJSViewCompiler.h"
#import "CBLJSShowFunctionCompiler.h"
#import "CBLJSListFunctionCompiler.h"
#import "CBLListener.h"
#import "CBLMisc.h"

#if DEBUG
#import "Logging.h"
#else
#define Warn NSLog
#define Log NSLog
#endif

@interface CBLAppDelegate()

@property (strong, nonatomic) CBLManager *manager;
@property (strong, nonatomic) CBLListener *listener;

@end

@implementation CBLAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
#if DEBUG
    EnableLog(YES);
    EnableLogTo(CBLListener, YES);
    //EnableLogTo(CBLListenerVerbose, YES);
    EnableLogTo(CBL_URLProtocol, YES);
    EnableLogTo(CBLRouter, YES);
    EnableLogTo(Sync, YES);
    EnableLogTo(View, YES);
    EnableLogTo(ViewIndexVerbose, NO);
    EnableLogTo(RemoteRequest, YES);
#endif
    
    [CBLView setCompiler: [[CBLJSViewCompiler alloc] init]];
    [CBLShowFunction setCompiler: [CBLJSShowFunctionCompiler new]];
    [CBLListFunction setCompiler: [CBLJSListFunctionCompiler new]];
    
    NSString* dataPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    CBLManagerOptions options = {}; options.readOnly = NO;
    NSError* error;
    _manager = [[CBLManager alloc] initWithDirectory: dataPath
                                             options: &options
                                               error: &error];
    if (error) {
        Warn(@"FATAL: Error initializing CouchbaseLite: %@", error);
        exit(EXIT_FAILURE);
    }
    LogMY(@"data dir: %@", dataPath);
    
    NSString *encryptionKey = nil;
    {
        NSDictionary *copyMatchingQuery = @{
                                            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                                            (__bridge id)kSecAttrService: @"sqlcipher",
                                            (__bridge id)kSecAttrAccount: @"encryption-key",
                                            (__bridge id)kSecReturnData: @YES
                                            };
        
        CFDataRef outData = NULL;
        OSStatus copyMatchingStatus = SecItemCopyMatching((__bridge CFDictionaryRef)copyMatchingQuery, (CFTypeRef *)&outData);
        NSData *data = (__bridge_transfer NSData*)outData;
        if (copyMatchingStatus == errSecSuccess) {
            encryptionKey = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
        else if (copyMatchingStatus == errSecItemNotFound) {
            // insert new key
            encryptionKey = CBLCreateUUID();
            data = [encryptionKey dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *addAttributes = @{
                                            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                                            (__bridge id)kSecAttrService: @"sqlcipher",
                                            (__bridge id)kSecAttrAccount: @"encryption-key",
                                            (__bridge id)kSecValueData: data
                                            };
            OSStatus addStaus = SecItemAdd((__bridge CFDictionaryRef)addAttributes, NULL);
            if (addStaus != errSecSuccess) {
                LogMY(@"FATAL: Error saving encryption key: %d", (int)addStaus);
                exit(EXIT_FAILURE);
            }
        }
        else {
            LogMY(@"FATAL: Error querying encryption key: %d", (int)copyMatchingStatus);
            exit(EXIT_FAILURE);
        }
    }
    _manager.encryptionKey = encryptionKey;

    // Start a listener socket:
    _listener = [[CBLListener alloc] initWithManager: _manager port: 59840];
    if (!_listener) {
        Warn(@"FATAL: Coudln't create CBLListener");
        exit(EXIT_FAILURE);
    }
    _listener.readOnly = options.readOnly;
    
    // Advertise via Bonjour, and set a TXT record just as an example:
    [_listener setBonjourName: @"LiteServ" type: @"_cbl._tcp."];
    NSData* value = [[UIDevice currentDevice].identifierForVendor.UUIDString dataUsingEncoding: NSUTF8StringEncoding];
    _listener.TXTRecordDictionary = @{@"Key": value};
    
    if (![_listener start: &error]) {
        Warn(@"FATAL: Failed to start HTTP listener: %@", error.localizedDescription);
        exit(EXIT_FAILURE);
    }
    
    LogMY(@"LiteServ %@ is listening%@ at <%@> ... relax!",
        CBLVersionString(),
        (_listener.readOnly ? @" in read-only mode" : @""),
        _listener.URL);
    
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    // Override point for customization after application launch.
    self.window.backgroundColor = [UIColor whiteColor];
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

@synthesize window = _window;
@synthesize manager = _manager;
@synthesize listener = _listener;

@end
