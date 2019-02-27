//
//  CBLMangoIndexUpdater.h
//  CouchbaseLite
//
//  Created by Alexander  Karaberov on 27.02.19.
//

#import <Foundation/Foundation.h>

@class CBLDatabase;

NS_ASSUME_NONNULL_BEGIN

@interface CBLMangoIndexUpdater : NSObject


/**
 Update a single index.
 
 The index is assumed to already exist.
 */
+ (BOOL)updateIndex:(NSString *)indexName
         withFields:(NSArray<NSString *> *)fieldNames
         inDatabase:(CBLDatabase *)database
  fromEventDatabase:(CBLDatabase *)eventDatabase
              error:(NSError *__nullable __autoreleasing *__nullable)error;

@end

NS_ASSUME_NONNULL_END
