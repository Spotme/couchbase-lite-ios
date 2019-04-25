//
//  CBLDatabase+MangoQuery.m
//  CouchbaseLite
//
//  Created by Alexander  Karaberov on 01.03.19.
//

#import "CBLDatabase+MangoQuery.h"
#import "CBLMangoIndexManager.h"
#import <objc/runtime.h>
#import "os/lock.h"

/**
  Several times faster than @synchronised, NSLock and pthread_mutex.
  @warning Supported since iOS 10.0. Hence if iOS 9 is still not dropped by the time this has to be merged to staging
           then fallback to pthread_mutex_lock.
 **/
os_unfair_lock mangoInitLock = OS_UNFAIR_LOCK_INIT;

@implementation CBLDatabase (MangoQuery)

@dynamic mangoIndexManager;


- (CBLMangoIndexManager *)mangoIndexManager
{
    os_unfair_lock_lock(&mangoInitLock);
    if (objc_getAssociatedObject(self, @selector(mangoIndexManager)) == nil) {
        CBLMangoIndexManager *indexManager = [[CBLMangoIndexManager alloc] initWithDatabase:self];
        
        objc_setAssociatedObject(self, @selector(mangoIndexManager), indexManager,
                                 OBJC_ASSOCIATION_RETAIN);
    }
    id indexManager = objc_getAssociatedObject(self, @selector(mangoIndexManager));
    os_unfair_lock_unlock(&mangoInitLock);
    return indexManager;
}


- (BOOL)activateMangoQueryEngine {
    if ([NSThread isMainThread]) {
        if (!self.mangoIndexManager) {
            LogTo(CBLDatabase, @"%@ index manager init error", self);
            return NO;
        }
        return YES;
    } else {
        [[NSAssertionHandler currentHandler] handleFailureInMethod:_cmd
                                                            object:self
                                                              file:@(__FILE__)
                                                        lineNumber:__LINE__
                                                       description:
         @"***** THREAD-SAFETY VIOLATION: CBLMangoIndexManager must be initialised on the main thread only *****"];
        return NO;
    }
}


- (void)ensureIndexed:(NSArray<NSString *> *)fieldNames
                   withName:(NSString *)indexName
                     ofType:(CBLMangoIndexType)type
          completionHandler:(MangoIndexCompletionBlock)completion {
    
    if (self.mangoIndexManager) {
        dispatch_async(self.mangoIndexManager.mangoQueryEngineDispatchQueue, ^{
            NSString *index = [self.mangoIndexManager ensureIndexed:fieldNames
                                                withName:indexName
                                                  ofType:CBLMangoIndexTypeJSON];
            completion(index);
        });
    } else {
        LogTo(CBLDatabase, @"%@ Fatal: CBLMangoIndexManager is not initialised", self);
        return;
    }
}


- (nullable CBLMangoResultSet *)find:(NSDictionary *)query {
    return nil;
}


- (nullable CBLMangoResultSet *)find:(NSDictionary *)query
                                skip:(NSUInteger)skip
                               limit:(NSUInteger)limit
                              fields:(nullable NSArray *)fields
                                sort:(nullable NSArray *)sortDocument {
    return nil;
}


@end
